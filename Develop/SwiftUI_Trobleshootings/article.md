내가 SwiftUI로 개발하면서 고민했던 내용 정리

# Observation - View Model이 여러 번 만들어지는 문제

Xcode 15.2 (15C500b) + iPhone 15 Pro Max 17.2 Simulator 기준

## 문제

아래 코드를 실행하고 Button을 누르면 init 0이 두 번 찍힘

```swift
import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            CounterView()
        }
    }
}

@Observable
class CounterViewModel {
    var count: Int
    
    init(count: Int) {
        self.count = count
        print("init", self.count)
    }
}

struct CounterView: View {
    @State private var viewModel: CounterViewModel = .init(count: .zero)
    
    var body: some View {
        Button(String(viewModel.count)) { 
            viewModel.count += 1
        }
    }
}
```

## 해결

`self.count` -> `self._count`로 바꾸면 됨

## 과정 - Observation Framework의 이해

### 기본

그냥 문서보셈 [Observation](https://developer.apple.com/documentation/observation)

이 글에서 기본적인 설명은 생략

UIKit에서는 쓰지마셈. Public API 만으로는 한계가 있음. 예를 들면 수동으로 cancel하는게 안 됨.

### 심화

[apple/swift - Observation](https://github.com/apple/swift/tree/main/stdlib/public/Observation/Sources/Observation)

크게 두 가지로 나뉨

- ObservationRegistrar
    - Public
    - @Observable macro를 쓰면 자동으로 생성되는 property인 `_$observationRegistrar`의 type이다.
    - Observer를 추가/삭제 할 수 있으나 Public API로는 직접 할 수 없다.
    - _ManagedCriticalState로 인해 Thread-safe하다.
    - [`access`](https://github.com/apple/swift/blob/81d77a68ee067a5fbc46a82639db060aa17c232d/stdlib/public/Observation/Sources/Observation/ObservationRegistrar.swift#L313)를 호출하면 Observer를 등록할 수 있으나 조건이 따른다. 현재 Thread의 TLS에서 key (0x6a)에 접근해서 ObservationTracking._AccessList을 가겨온 뒤, ObservationTracking._AccessList에 등록만 한다. 실제 ObservationRegistrar에 등록하는 것은 access에서 이뤄지지 않는다. 이는 후술한다.

- ObservationTracking
    - @_spi(SwiftUI)를 통해 SwiftUI에만 Public이다.
        `@_spi(SwiftUI) import Observation`을 하면 다른 Module에서도 사용할 수 있으나, Xcode의 기본 Toolchain에서는 `.private.swiftinterface`를 제공하지 않는다. Swift 공홈에서 제공하는 Toolchain에서는 제공하므로 이걸 쓰면 된다.
    - Observer를 등록하기 위한 첫번째 관문 API다.
    - [`generateAccessList`](https://github.com/apple/swift/blob/81d77a68ee067a5fbc46a82639db060aa17c232d/stdlib/public/Observation/Sources/Observation/ObservationTracking.swift#L157)이 흥미로운 부분인데
        - 우선 기존 TLS 값을 벡업하고, TLS에 새로운 ObservationTracking._AccessList를 할당하고
        - apply block을 호출하면서 `access`가 불리면서 ObservationTracking._AccessList에 Observer 정보가 추가될거고
        - 백업한 정보와 합쳐서 Observer를 설치한다. 그리고 백업한 값을 다시 TLS에 돌려 놓는다.

여기서 이게 왜 Thread-safe하냐면

- withObservationTracking를 여러 Thread에서 동시에 호출해도, ObservationTracking은 각자 독립적으로 TLS에서 값을 일어오기만 하므로 Thread-safe하고, 최종적으로 ObservationRegistrar에 등록하는데
- 상술했다시피 ObservationRegistrar 자체는 _ManagedCriticalState로 Thread-safe하다.

또한 나는 아래처럼 `car.name`을 호출하는 것 만으로 (= access를 호출하는 것 만으로) Observer를 등록되게 하기 위해 TLS를 사용한 것은 참신하다고 생각한다. Thread-safe하기도 하고.

```swift
func render() {
    withObservationTracking {
        for car in cars {
            print(car.name)
        }
    } onChange: {
        print("Schedule renderer.")
    }
}
```

나머지 내용은 Observer 기능을 구현하기 위한 흔한 코드라 굳이 다룰 필요는 없을 것 같음.

## 과정 - SwiftUI에서 Observation Framework를 어떻게 다루는가

SwiftUI의 내부가 너무 변칙적이라 분석에 굉장히 애를 먹었다.

- SwiftUI의 Update Cycle이 시작될 때 (아마도 `AG::Graph::UpdateStack::update`), `pthread_getspecific(0x6a)`에 새로운 ObservationTracking._AccessList을 할당한다.
    - [ObservationTracking._AccessList.init](https://github.com/apple/swift/blob/81d77a68ee067a5fbc46a82639db060aa17c232d/stdlib/public/Observation/Sources/Observation/ObservationTracking.swift#L56)이 internal이어서 직접 struct를 alloc한 것으로 보인다. symbol (`$s11Observation0A8TrackingVyA2C11_AccessListVSgcfC`)로 breakpoint를 걸면 안 잡히지만 `expr -l c -- (void *)pthread_getspecific(0x6a)` 찍으면 값이 잘 나오는 것을 확인할 수 있으며 `breakpoint set -n pthread_getspecific -C '$x0 == 0x6a'`로 breakpoint를 걸 수 있다.

- View의 데이터 (struct)를 생성하고, 만약 `ObservationTracking._AccessList`이 비어 있지 않다면 _installTracking을 호출해서 TLS에 있는 `ObservationTracking._AccessList`로 View의 갱신 조건으로 설정한다.

    - **이게 문제의 원인이다.** 이 과정에서 `CounterViewModel.init`이 발생하는데, 여기서 `self.count`가 발동되면 `\.count`의 access가 불리면서 View의 재갱신 조건에 `\.count`가 들어가 버리게 된다.

- 새로운 Update Cycle에서 View의 body를 생성하고, 만약 `ObservationTracking._AccessList`이 비어 있지 않다면 _installTracking을 호출해서 TLS에 있는 `ObservationTracking._AccessList`로 body의 갱신 조건으로 설정한다.

- ObservationRegistrar이 일어난다면 View를 업데이트 한 후, 기존 tracking을 cancel하고 (`$s11Observation0A8TrackingV6cancelyyF`) 다시 옵저빙한다.


