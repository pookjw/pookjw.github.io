# iPad에서 SwiftUI NavigationView의 Display Mode Button을 없애기

![](1.png)

iPad에서 SwiftUI로 NavigationView을 쓸 경우, 좌측 상단에 Display Mode Button이 뜨는데, 아무리 찾아봐도 이걸 지우는 방법이 안 나오길래 만든 방법입니다.

```swift
import SwiftUI

func setDisplayModeButtonVisibilityHidden() {
    typealias BlockType = @convention(c) (Any, Selector, UISplitViewController.Style) -> Any
    
    let selector: Selector = #selector(UISplitViewController.init(style:))
    let method: Method = class_getInstanceMethod(NSClassFromString("SwiftUI.NotifyingMulticolumnSplitViewController"), selector)!
    let originalImp: IMP = method_getImplementation(method)
    let original: BlockType = unsafeBitCast(originalImp, to: BlockType.self)
    
    let new: @convention(block) (Any, UISplitViewController.Style) -> Any = { (me, arg0) -> Any in
        let object: UISplitViewController = original(me, selector, arg0) as! UISplitViewController
        object.displayModeButtonVisibility = .never
        return object
    }
    
    let newImp: IMP = imp_implementationWithBlock(new)
    method_setImplementation(method, newImp)
}
``` 

이렇게 `setDisplayModeButtonVisibilityHidden()`라는 함수를 정의하고

```swift
@main
struct MyApp: App {
    init() {
        setDisplayModeButtonVisibilityHidden()
    }
}
```

`@main`이 정의된 `App`의 `init()`에서 새로 만든 함수를 호출하면

![](2.png)

이렇게 버튼이 사라지는 것을 볼 수 있습니다.

---

SwiftUI에서 Split Layout을 구현할 때 `UISplitViewController`를 상속하는 `NotifyingMulticolumnSplitViewController`라는 것을 쓰고 있는데, 좀 동작이 다른 것 같네요.
