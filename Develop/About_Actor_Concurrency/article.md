# [Swift Concurrency] Actor는 동시 접근 방지를 항상 보장하지 않는다.

> “There ain’t no such thing as a free lunch.” —R. A. Heinlein, The Moon Is a Harsh Mistress
> - [The Free Lunch Is Over: A Fundamental Turn Toward Concurrency in Software (2005)](http://www.gotw.ca/publications/concurrency-ddj.htm)
>
> 싱글스레드 코드로 공짜 점심을 먹던 시대는 끝났다.

아래와 같은 코드가 있다고 가정합시다.

```swift
actor Cloth {
    private(set) var purchasedCount: Int = .zero
    
    func purchase() async {
        guard purchasedCount == .zero else { return }
        await communicateWithBackend()
        purchasedCount += 1
    }
    
    private nonisolated func communicateWithBackend() async {
        try! await Task.sleep(for: .seconds(1))
    }
}

@main
struct MyScript {
    static func main() async {
        let cloth: Cloth = .init()
        
        let t1 = Task {
            await cloth.purchase()
        }
        
        
        let t2 = Task {
            await cloth.purchase()
        }
        
        await t1.value
        await t2.value
        
        await print(cloth.purchasedCount) // 2
    }
}
```

- `Cloth`라는 actor가 있습니다. 딱 1회만 구입이 가능하며, 2회 이상 구입하는 것을 방지합니다.

- 하지만 `Task.detached`를 통해 구입을 2회 시도했더니 2회 구입이 되었네요.

actor는 동시 접근을 방지하려는 것으로 알고 있어서 위와 같은 코드를 짰는데, 생각이랑 다르게 동작하고 있습니다.

이유는 `communicateWithBackend`에서 context switching이 일어났기 때문입니다. 그렇다고 isolated 환경에서 NSLock, OSAllocatedUnfairLock, DispatchSemaphore 같은 API를 호출하는 것도 좋은 아이디어는 아닌 것 같고요.

이를 가능하게 하기 위해서 `AsyncMutex`라는 것을 만들었어요.

```swift
import Foundation

actor AsyncMutex {
    private var isLocked: Bool = false
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = .init()
    
    deinit {
        continuations.forEach { $0.value.finish() }
    }
    
    private var stream: AsyncStream<Void> {
        let (stream, continuation): (AsyncStream<Void>, AsyncStream<Void>.Continuation) = AsyncStream<Void>.makeStream()
        let key: UUID = .init()
        
        continuation.onTermination = { [weak self] _ in
            Task { [weak self] in
                await self?.remove(key: key)
            }
        }
        
        continuations[key] = continuation
        
        return stream
    }
    
    func lock() async {
        mutexLoop: while isLocked {
            for await _ in stream {
                if !isLocked {
                    break mutexLoop
                }
            }
        }
        
        isLocked = true
    }
    
    func unlock() async {
        isLocked = false
        continuations.forEach { $0.value.yield() }
    }
    
    private func remove(key: UUID) {
        continuations.removeValue(forKey: key)
    }
}
```

이걸로 아래와 같이 동시 접근 방지 코드를 짤 수 있어요. 잘 작동하는 것을 보실 수 있어요.

```swift
actor Cloth {
    private(set) var purchasedCount: Int = .zero
    private let mutex: AsyncMutex = .init()
    
    func purchase() async {
        await mutex.lock()
        
        guard purchasedCount == .zero else {
            await mutex.unlock()
            return
        }
        await communicateWithBackend()
        purchasedCount += 1
        await mutex.unlock()
    }
    
    private nonisolated func communicateWithBackend() async {
        try! await Task.sleep(for: .seconds(1))
    }
}

@main
struct MyScript {
    static func main() async {
        let cloth: Cloth = .init()
        
        let t1 = Task {
            await cloth.purchase()
        }
        
        
        let t2 = Task {
            await cloth.purchase()
        }
        
        
        let t3 = Task {
            await cloth.purchase()
        }
        
        await t1.value
        await t2.value
        await t3.value
        
        await print(cloth.purchasedCount) // 1
    }
}
```

## 여담

### Task.sleep -> Thread.sleep으로 대체하면 해결되기도 합니다.

아래 코드를

```swift
private func communicateWithBackend() async {
    try! await Task.sleep(for: .seconds(1))
}
```

아래처럼 Task.sleep -> Thread.sleep로 대체하면 작동하긴 해요. 물론 Warning은 뜨지만요. (아마 `@_unavailableFromAsync` 때문인듯)

```swift
private func communicateWithBackend() async {
    // Warning: Class method 'sleep' is unavailable from asynchronous contexts; Use Task.sleep(until:clock:) instead.; this is an error in Swift 6
    Thread.sleep(forTimeInterval: 1)
}
```

이유는 Task.sleep은 context를 양보하게 되는데, Thread.sleep은 자기 context를 계속 붙잡아서 양보를 안해준다는 차이점 입니다.

### C++에서 std::mutex로 동시 접근 방지하기

```cpp
#include <stdio.h>
#include <thread>
#include <mutex>
#include <memory>
#include <cinttypes>
#include <chrono>

class Cloth {
public:
    void purchase() {
        mtx.lock();
        if (count != 0) {
            return;
        }
        communicateWithBackend();
        std::printf("%llu", ++count);
        mtx.unlock();
    }
private:
    std::mutex mtx;
    std::uint64_t count;
    void communicateWithBackend() {
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }
};

void foo(const std::shared_ptr<Cloth> &cloth) {
    cloth.get()->purchase();
}

int main(int argc, const char * argv[]) {
    const std::shared_ptr<Cloth> cloth {new Cloth};
    std::thread t1(foo, cloth);
    std::thread t2(foo, cloth);
    
    t1.join();
    t2.join();
    
    dispatch_main();
    return 0;
}

```
