# [visionOS 1] MRUIStage

(WWDC23 Session 영상이나 문서 안 봤고 그냥 실험해본거 적는 글이라 틀릴 수도 있음...)

watchOS에 PepperUICore가 있듯, visionOS에도 MRUIKit이 도입되었다. 기존 iOS UIKit에 visionOS용 Category가 붙었다고 보면 된다.

PepperUICore와 마찬가지로 MRUIKit도 Private Framework다. 내부를 보니 애플은 Public으로 풀어줄 생각 없어 보인다 ㅎ

MRUIKit의 내부 구조를 보다가 MRUIStage라는 것을 발견했다. UIWindowScene의 상위 개념이다. 우선 iOS에서 UI 구조는 아래와 같다.

```
UIScreen -> UIWindowScene -> UIWindow -> UIViewController -> UIView
```

MRUIStage는 UIScreen와 UIWindowScene의 중간 개념이다.

```
UIScreen -> MRUIStage -> UIWindowScene -> UIWindow -> UIViewController -> UIView
```

- 말 그대로 무대이다. UIWindowScene은 UIWindow를 관리한다면 (macOS로 치면 NSWindowController 느낌), MRUIStage는 Window가 띄워지는 무대를 관리한다.

- MRUIStage는 여러 개의 UIWindowScene를 가진다.

- active/inactive의 Life Cycle이 존재한다.

이해를 돕기 위해 아래처럼 MobileSafari에서 2개의 Stage를 띄웠다고 하자

![](0.gif)


