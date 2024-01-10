내가 SwiftUI로 개발하면서 고민했던 내용 정리

# Observation - View Model이 여러 번 만들어지는 문제

Xcode 15.2 (15C500b) + iPhone 15 Pro Max 17.2 Simulator + Swift Trunk Development (main, January 8, 2024) 기준

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

### 부록

Swift Toolchain으로 `@_spi(SwiftUI)` API 호출해서 UIKit에서 ObservationRegistrar를 옵저빙하는 예시 코드

```swift
import UIKit
@_spi(SwiftUI) import Observation

@Observable
class ViewModel {
    var number: Int
    
    init(number: Int) {
        self.number = number
    }
}

class ViewController: UIViewController {
    @ViewLoading @IBOutlet var button: UIButton
    var viewModel: ViewModel!
    var viewModelTracking: ObservationTracking!
    var numberTracking: ObservationTracking!
    
    private func configureViewModel() {
        viewModel = withObservationTracking(
            { 
                let viewModel: ViewModel = .init(number: .zero)
                return viewModel
            },
            didSet: { [weak self] tracking in
                guard let self else { return }
                self.viewModelTracking?.cancel()
                self.viewModelTracking = tracking
                self.configureViewModel()
                self.observeNumber(viewModel: viewModel)
            }
        )
    }
    
    private func observeNumber(viewModel: ViewModel) {
        withObservationTracking(
            {
                _ = viewModel.number
            },
            didSet: { [weak self] tracking in
                guard let self else { return }
                self.numberTracking?.cancel()
                self.numberTracking = tracking
                self.observeNumber(viewModel: viewModel)
                
                Task { @MainActor in
                    var configuration: UIButton.Configuration = .plain()
                    configuration.title = self.viewModel.number.description
                    self.button.configuration = configuration
                }
            }
        )
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViewModel()
        observeNumber(viewModel: viewModel)
    }

    @IBAction func increment(_ sender: Any) {
        viewModel.number += 1
    }
}
```

# SwiftUI - Retain Cycle

Xcode 15.2 (15C500b) + iPhone 15 Pro Max 17.2 Simulator 기준

아래 코드를 실행하고 Present CounterView → Dismiss 버튼을 누르면 CounterViewModel가 deinit 되지 않는다.

```swift
import SwiftUI

struct ContentView: View {
    @State var isPresentingSheet: Bool = false
    
    var body: some View {
        Button("Present") {
            isPresentingSheet = true
        }
        .sheet(isPresented: $isPresentingSheet) {
            SecondaryView()
        }
    }
}

final class MyObject: NSObject {
    override init() {
        super.init()
        print("MyObject.init")
    }
    
    deinit {
        print("Never called")
    }
}

struct SecondaryView: View {
    @State var handler: (() -> Void)?
    let myObject: MyObject = .init()
    var body: some View {
        Color.clear
            .task {
                handler = { _ = myObject }
            }
    }
}
```

## 해결

myObject만 capture

```swift
handler = { [myObject] _ = myObject }
```

## 과정

`SwiftUI.StoredLocation`에서 Retain Cycle이 발생하여, `CounterViewModel`이 Storage에 계속 붙잡히고 있는 문제다.

Retain Cycle이 발생하는 이유는 `handler`가 생성될 때의 assembly를 보면

```swift
    0x1042c9e7c <+176>: ldr    x0, [sp, #0x20]
    0x1042c9e80 <+180>: str    x2, [x1, #0x10]
    0x1042c9e84 <+184>: str    x3, [x1, #0x18]
    0x1042c9e88 <+188>: str    x4, [x1, #0x20]
    0x1042c9e8c <+192>: str    x5, [x1, #0x28]
->  0x1042c9e90 <+196>: bl     0x1042c9238               ; MyApp.SecondaryView.handler.setter : Swift.Optional<() -> ()> at MyAppApp.swift:44

(lldb) expr -l c -O -- $x4
SwiftUI.StoredLocation<Swift.Optional<() -> ()>>
```

handler에는 총 4개의 값이 capture되며, 그 중 마지막이 StoredLocation다.

즉, StoredLocation는 handler를 capture하고 handler는 StoredLocation를 capture하므로 retain cycle이 발생한다.

# iOS 17.0..<17.2의 SwiftUI Presentation에서 Leak

Xcode 15.1 (15C65), iPhone 15 Pro Max 17.0.1 Simulator 기준 (iOS 17.2에서 해결된 SwiftUI 버그)

유명한 버그이기도 하다. 아래 코드에서 Present를 하고 dismiss를 하면 ViewModel의 메모리가 해제되지 않는다.

```swift
import SwiftUI

@main
struct MyAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
  @State private var isPresenting: Bool = false

  var body: some View {
      Button("Present") {
        isPresenting = true
      }
    .fullScreenCover(isPresented: $isPresenting) {
        SheetView()
    }
  }
}

struct SheetView: View {
  @Environment(\.dismiss) var dismiss
  private let viewModel: ViewModel = .init()

  var body: some View {
    Button("Dismiss") {
      dismiss()
    }
  }
}

class ViewModel {
  init() {
    print("init")
  }

  deinit {
    print("deinit")
  }
}
```

## 해결

- SwiftUI의 Presentation 방식을 안 쓰고 UIKit Presentation 방식을 쓰면 된다. [링크](https://developer.apple.com/forums/thread/737967?answerId=767599022#767599022)

- Leak이 나는 객체의 메모리를 강제로 해제시켜준다. [링크](https://github.com/pookjw/FixSwiftUIMemoryLeak) 미친 짓이니 그냥 참고로만 ㅎ

## 과정

Memory Inspector로 보면 AnyViewStorage라는 객체가 ViewModel를 retain하고 있고, AnyViewStorage는 Retain Count를 2~4 정도로 Leak이 걸린다.

아마 SwiftUI에서 내부적으로 Retain Count를 관리하고 있는 것 같은데, 관리가 잘못 되어서 Leak이 난 것으로 의심된다.

이 AnyViewStorage는 `_TtGC7SwiftUI29PresentationHostingControllerVS_7AnyView_`에서 아래처럼 Mirror를 활용하면 가져올 수 있다.

```swift
let hostingController: SwiftUI.PresentationHostingController<AnyView> = /* */

if 
  let delegate = Mirror(reflecting: hostingController).children.first(where: { $0.label == "delegate" })?.value,
  let some = Mirror(reflecting: delegate).children.first(where: { $0.label == "some" })?.value,
  let presentationState = Mirror(reflecting: some).children.first(where: { $0.label == "presentationState" })?.value,
  let base = Mirror(reflecting: presentationState).children.first(where: { $0.label == "base" })?.value,
  let requestedPresentation = Mirror(reflecting: base).children.first(where: { $0.label == "requestedPresentation" })?.value,
  let value = Mirror(reflecting: requestedPresentation).children.first(where: { $0.label == ".0" })?.value,
  let content = Mirror(reflecting: value).children.first(where: { $0.label == "content" })?.value,
  let storage = Mirror(reflecting: content).children.first(where: { $0.label == "storage" })?.value
{
  /* storage */
}
```

따라서 `_TtGC7SwiftUI29PresentationHostingControllerVS_7AnyView_`이 안 만들어지게 한다면, 다시 말해 UIKit Presentation으로 대체한다면 문제가 해결된다.

아니면 내가 꼼수로 만든 [`View+fixMemoryLeak.swift`](https://github.com/pookjw/FixSwiftUIMemoryLeak/blob/main/MyApp/View%2BfixMemoryLeak.swift)로 View가 사라질 때 AnyViewStorage의 메모리를 강제로 해제시켜주면 해결되기도 한다. 하지만 코드를 보면 알겠지만 메모리를 강제로 해제시키는 타이밍이 애매하다. (RunLoop에 언제 불릴지 모를 동작을 추가하는 것은 애매하다.) 이는 개선해야 한다.
