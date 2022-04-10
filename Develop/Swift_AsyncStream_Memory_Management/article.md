# Swift AsyncStream + 메모리 관리

[AsyncStream](https://developer.apple.com/documentation/swift/asyncstream)을 쓰면서 메모리 관리를 하는 팁을 소개하려고 합니다.

예시를 들어서 설명하겠습니다. `DataCacheRepo`와 `DataCacheUseCase`, `DataCacheUseCaseImpl`이 아래와 같이 있다고 가정해 봅시다.

```swift
protocol DataCacheRepo {
    var didChangeDataCache: AsyncThrowingStream<Void, Swift.Error> { get }
}
```

```swift
public protocol DataCacheUseCase {
    var didChangeDataCache: AsyncThrowingStream<Void, Swift.Error> { get }
}

public final class DataCacheUseCaseImpl: DataCacheUseCase {
    public nonisolated var didChangeDataCache: AsyncThrowingStream<Void, Error> {
        .init { [self] continuation in
            Task {
                for try await value in self.dataCacheRepo.didChangeDataCache {
                    continuation.yield(value)
                }
            }
        }
    }

    private let dataCacheRepo: DataCacheRepo
}
```

`DataCacheRepo.didChangeDataCache`에 날라오는 이벤트를 `DataCacheUseCaseImpl.didChangeDataCache`에 Binding하는 구조입니다. 이 `DataCacheUseCaseImpl.didChangeDataCache`를 아래처럼 옵저빙을 시작한다면

```swift
let task: Task = .init {
    for try await _ in dataCacheUseCase.didChangeDataCache {

    }
}
```

`DataCacheUseCaseImpl.didChangeDataCache`에서 `dataCacheUseCase (self)`를 strong 참조하고 있기 때문에, 순환참조가 발생해서 `task`가 cancel이 되어도 `dataCacheUseCase`는 deinit되지 않는 문제가 발생합니다.

'그러면 `[self]` 대신에 `[weak self]`를 쓰면 되는거 아니야?'라고 생각하실 수 있습니다. 하지만 `for`문 특성상 `guard let self = self else { return }`은 무조건 써야 하므로, `DataCacheUseCaseImpl`의 코드는 아래와 같이 바뀌겠네요.

```swift
public final class DataCacheUseCaseImpl: DataCacheUseCase {
    public nonisolated var didChangeDataCache: AsyncThrowingStream<Void, Error> {
        .init { [weak self] continuation in
            Task { [weak self] in
                guard let self = self else { return }
                for try await value in self.dataCacheRepo.didChangeDataCache {
                    continuation.yield(value)
                }
            }
        }
    }

    private let dataCacheRepo: DataCacheRepo
}
``` 

... 하지만 `guard let self = self else { return }`에서 self를 strong 참조를 하게 되고, Task는 영원히 끝나지 않기 때문에 순환참조가 해결되지 않습니다. `[unowned self]`를 쓰면 해결되겠지만, Race Condition이 발생하지 않을거란 보장이 없습니다. 즉, 저희는 `AsyncThrowingStream` (또는 `AsyncStream`) 내에서는 self의 Reference Count를 늘리면 안 됩니다. 그러면 `[self]` 또는 `[weak self]` 대신에, `[dataCacheRepo]`로 고쳐볼게요.

```swift
public final class DataCacheUseCaseImpl: DataCacheUseCase {
    public nonisolated var didChangeDataCache: AsyncThrowingStream<Void, Error> {
        .init { [dataCacheRepo] continuation in
            Task { [dataCacheRepo] in
                for try await value in dataCacheRepo.didChangeDataCache {
                    continuation.yield(value)
                }
            }
        }
    }

    private let dataCacheRepo: DataCacheRepo
}
``` 

이렇게 하니 순환참조 문제는 해결됩니다! 하지만 `dataCacheRepo.didChangeDataCache`이 끝나지 않는다면 `Task`가 영원히 끝나지 않는 또 다른 문제가 발생합니다.😭😭😭😭😭😭😭😭😭😭😭😭

그럴 때는 [`AsyncStream.Continuation.onTermination`](https://developer.apple.com/documentation/swift/asyncstream/continuation/3856653-ontermination)을 활용하면 됩니다. 아래처럼요.

```swift
public final class DataCacheUseCaseImpl: DataCacheUseCase {
    public nonisolated var didChangeDataCache: AsyncThrowingStream<Void, Error> {
        .init { [dataCacheRepo] continuation in
            let task: Task = .init { [dataCacheRepo] in
                for try await value in dataCacheRepo.didChangeDataCache {
                    continuation.yield(value)
                }
            }
            
            continuation.onTermination = { termination in
                task.cancel()
            }
        }
    }

    private let dataCacheRepo: DataCacheRepo
}
```

이렇게 하면 `AsyncThrowingStream` (또는 `AsyncStream`)이 끝났을 때 `task`도 끝나게 할 수 있습니다. 근데 또 다른 문제가 발생합니다. `dataCacheRepo`를 strong으로 잡고 있기 때문인데요... ㅋㅋㅋㅋ

이럴 때는 `AsyncThrowingStream.Continuation`을 property로 빼낸 다음에, `DataCacheUseCaseImpl.deinit` 시점에서 finish를 해주면 됩니다.

```swift
public final class DataCacheUseCaseImpl: DataCacheUseCase {
    public nonisolated var didChangeDataCache: AsyncThrowingStream<Void, Error> {
        .init { [dataCacheRepo, weak self] continuation in
            let task: Task = .init { [dataCacheRepo, weak self] in
                self?.didChangeDataCacheContinuations.append(continuation)
                
                for try await value in dataCacheRepo.didChangeDataCache {
                    continuation.yield(value)
                }
            }
            
            continuation.onTermination = { termination in
                task.cancel()
            }
        }
    }
    
    private let dataCacheRepo: DataCacheRepo
    private lazy var didChangeDataCacheContinuations: [AsyncThrowingStream<Void, Error>.Continuation] = []
    
    deinit {
        didChangeDataCacheContinuations.forEach { $0.finish() }
    }
}
```

이렇게 되면 `DataCacheUseCaseImpl`이 deinit되는 시점에 스트림을 끝낼 수 있고, strong으로 붙잡히고 있던 `dataCacheRepo`도 풀려나게 됩니다.

근데 `didChangeDataCache` 스트림이 끝나도 `didChangeDataCacheContinuations`에 저장된 `continuation`이 지워지지 않는 문제가 발생하므로, [`withTaskCancellationHandler(handler:operation:)`](https://developer.apple.com/documentation/swift/3814990-withtaskcancellationhandler)를 써줍시다.

```swift
public final class DataCacheUseCaseImpl: DataCacheUseCase {
    public nonisolated var didChangeDataCache: AsyncThrowingStream<Void, Error> {
        .init { [dataCacheRepo, weak self] continuation in
            let task: Task = .init { [dataCacheRepo, weak self] in
                self?.didChangeDataCacheContinuations.append(continuation)
                
                try await withTaskCancellationHandler(
                    handler: { [weak self] in
                        self?.didChangeDataCacheContinuations.removeAll { i in
                            let first: UnsafePointer<AsyncThrowingStream<Void, Error>.Continuation> = withUnsafePointer(to: i, { UnsafePointer($0) })
                            let second: UnsafePointer<AsyncThrowingStream<Void, Error>.Continuation> = withUnsafePointer(to: continuation, { UnsafePointer($0) })
                            return first == second
                        }
                    },
                    operation: {
                        for try await _ in dataCacheRepo.didChangeDataCache {
                            continuation.yield(())
                        }
                    }
                )
            }
            
            continuation.onTermination = { termination in
                task.cancel()
            }
        }
    }
    
    private let dataCacheRepo: DataCacheRepo
    private lazy var didChangeDataCacheContinuations: [AsyncThrowingStream<Void, Error>.Continuation] = []
    
    deinit {
        didChangeDataCacheContinuations.forEach { $0.finish() }
    }
}
```

즉, 요약하면 저희는 아래를 보장할 수 있게 됩니다.

- `dataCacheRepo.didChangeDataCache`의 스트림이 끝나면 strong으로 붙잡고 있던게 모두 풀립니다.

- 또한 `DataCacheUseCaseImpl`가 deinit이 되면 스트림을 끝낼 수 있고, strong으로 붙잡고 있던게 모두 풀립니다.

- `DataCacheUseCaseImpl.didChangeDataCache` 스트림을 cancel할 경우에도 strong으로 붙잡고 있던게 모두 풀립니다.

### 같이 읽으면 좋은 자료

[Memory management when using async/await in Swift](https://www.swiftbysundell.com/articles/memory-management-when-using-async-await/)
