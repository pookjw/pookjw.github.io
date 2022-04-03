# Swift TaskGroup + Batch Size

Swift Concurrency에는 child task들을 관리할 수 있는 [TaskGroup](https://developer.apple.com/documentation/swift/taskgroup)이 있습니다.

```swift
let images: [UIImage] = await withTaskGroup(of: Data.self, returning: [UIImage].self) { group in
    urls.forEach { url in
        group.addTask {
            return try! await URLSession.shared.data(from: url).0
        }
    }
    
    return await group.reduce(into: [UIImage](), { partialResult, data in
        if let image: UIImage = .init(data: data) {
            partialResult.append(image)
        }
    })
}
```

하지만 실행시켜야 할 task가 너무 많으면 그 많은 것들을 동시에 실행시키면 부하가 있으므로, 동시간에 최대로 돌아갈 수 있는 Task 개수를 제한하고 싶을 때가 있습니다. [NSOperationQueue](https://developer.apple.com/documentation/foundation/nsoperationqueue)에서는 [maxConcurrentOperationCount](https://developer.apple.com/documentation/foundation/nsoperationqueue/1414982-maxconcurrentoperationcount)를 통해 통제할 수 있지만, Concurrency는 (아마도) 이런게 없는 것 같아요.

그래서 같은 기능을 수행할 수 있도록 `MaxTaskGroup`이라는 것을 만들어 봤는데요.

```swift
class MaxTaskGroup<Success> {
    private let maxTaskCount: Int
    private let total: Int
    private let operation: @Sendable (Int) async -> Success
    
    init(maxTaskCount: Int, total: Int, operation: @escaping @Sendable (Int) async -> Success) {
        self.maxTaskCount = maxTaskCount
        self.total = total
        self.operation = operation
    }
    
    var value: AsyncStream<Success> {
        get {
            AsyncStream<Success> { continuation in
                Task {
                    await withTaskGroup(of: Success.self) { group in
                        let batchSize: Int = self.maxTaskCount
                        
                        for i in 0..<batchSize {
                            group.addTask {
                                await self.operation(i)
                            }
                        }
                        
                        var index: Int = batchSize
                        
                        for await value in group {
                            continuation.yield(value)
                            
                            if index < self.total {
                                group.addTask { [index] in
                                    await self.operation(index)
                                }
                                index += 1
                            }
                        }
                        
                        continuation.finish()
                    }
                }
            }
        }
    }
}
```

따라서 처음에 소개드린 코드를 아래와 같이 개선할 수 있습니다.

```swift
let images = MaxTaskGroup(maxTaskCount: 4, total: urls.count) { index in
    try! await URLSession.shared.data(from: urls[index]).0
}
.value
.compactMap { data in
    UIImage(data: data)
}

for await image in images {
    
}
```

## TODO

Error Handling
