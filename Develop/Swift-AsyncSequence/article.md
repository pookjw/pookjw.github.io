# Swift AsyncSequence

AsyncSequence의 기초에 대해 적어보려고 합니다.

[Modern Concurrency in Swift (raywenderlich.com)](https://www.raywenderlich.com/books/modern-concurrency-in-swift) 내용의 일부 + 사족? 입니다.

## AsyncStream

딱 보자마자 느낀건 RxSwift의 Observable, Combine의 Publisher와 굉장히 유사합니다.

```swift
let counter = AsyncStream<String> { continuation in
  var countdown = 3
  
  Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
    guard countdown > 0 else {
      timer.invalidate()
      continuation.yield(with: .success("🎉 " + message))
      continuation.finish()
      return
    }
    
    continuation.yield("\(countdown) ...")
    countdown -= 1
  }
}

for await countdownMessage in counter {
  print(countdownMessage)
}
```

이런 식으로 카운트를 짤 수 있어요. Observable/Publisher와 굉장히 유사하죠. 근데 cancel이 나도 Timer가 안 끝나는 문제가 있는데요. 아마 raywenderlich에서 AsyncStream을 보여주려고 일부러 저렇게 한 것 같은데... 아래와 같이 개선이 가능해요.

```swift
var countdown = 3

let timerSequence = Timer
  .publish(every: 1, tolerance: 0, on: .main, in: .common, options: nil)
  .autoconnect()
  .values

for await _ in timerSequence {
  guard countdown > 0 else {
    print("🎉 " + message)
    break
  }
  
  print("\(countdown) ...")
  countdown -= 1
}
```

위 코드는 Combine을 썼는데... RxSwift에도 async/await 지원이 있다던데 될지도?


## AsyncSequence와 AsyncIteratorProtocol

```swift
struct TypeWriterIterator: AsyncIteratorProtocol {
    typealias Element = String
    
    let phrase: String
    var index: String.Index
    
    init(_ phrase: String) {
        self.phrase = phrase
        self.index = phrase.startIndex
    }
    
    mutating func next() async throws -> String? {
        guard index < phrase.endIndex else {
            return nil
        }
        
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        defer {
            index = phrase.index(after: index)
        }
        
        return String(phrase[phrase.startIndex...index])
    }
}

struct TypeWriter: AsyncSequence {
    typealias AsyncIterator = TypeWriterIterator
    
    typealias Element = String
    
    let phrase: String
    
    func makeAsyncIterator() -> TypeWriterIterator {
        return TypeWriterIterator(phrase)
    }
}
```

```swift
for try await item in TypeWriter(phrase: "Hello, World") {
    print(item)
}
```

결과

```
H
He
Hel
Hell
Hello
Hello,
Hello, 
Hello, W
Hello, Wo
Hello, Wor
Hello, Worl
Hello, World
```

다만 cancel이 일어나도 `Thread.sleep`이 안 끝나는 문제가 있는데... 요것도 Combine 쓰면 해결될듯?
