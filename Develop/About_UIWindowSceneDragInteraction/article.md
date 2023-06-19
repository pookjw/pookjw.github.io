# [iOS 17] UIWindowSceneDragInteraction

드디어 iOS에서도 [`-[NSWindow movableByWindowBackground]`](https://developer.apple.com/documentation/appkit/nswindow/1419072-movablebywindowbackground) 같은 API가 추가되었다.

 [UIWindowSceneDragInteraction](https://developer.apple.com/documentation/uikit/uiwindowscenedraginteraction)

Stage Manager 환경에서 View를 Drag하면 UIWindowScene의 위치를 움직이게 하는 API다.

```objc
#import <objc/message.h>

@interface WindowSceneDragInteractionViewController ()

@end

@implementation WindowSceneDragInteractionViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemPurpleColor;
    
    UIWindowSceneDragInteraction *interaction = [UIWindowSceneDragInteraction new];
    [self.view addInteraction:interaction];
    
    // _UIWindowSceneDragInteractionImpl_iOS
    NSLog(@"%@", ((id (*)(id, SEL))objc_msgSend)(interaction, NSSelectorFromString(@"impl")));
    
    [interaction release];
}

@end
```

간단하게 내부 구조를 보면

- `-impl`에서 `_UIWindowSceneDragInteractionImpl_iOS`라는 것을 가지고 있음 (Platform마다 다를듯 - macOS의 경우 아마 NSWindow의 frame을 직접 건들지 않을까? iOS는 그게 안 되니 FBScene -> XPC -> SpringBoard로 바꿔줌)

- `_UIWindowSceneDragInteractionImpl_iOS`은 `-_wrappedRecognizerDidRecognize:`를 가지고 있음. 내부적으로 가지고 있는 `UIPanGestureRecognizer`에서 이벤트를 보냄

- `-_wrappedRecognizerDidRecognize:`에서는 `_UIClientToHostGestureChangeAction (subclass of BSAction)`을 FBScene에 보냄

```objc
(lldb) po $x2
{(
    <_UIClientToHostGestureChangeAction: 0x2826807c0; info: <BSSettings: 0x28268ad20> {
    (0) = wndwdrag;
    (1) = 1;
}; responder: <_BSActionResponder: 0x280d602a0; active: YES> clientInvalidated = NO;
clientEncoded = NO;>
)}
```

- wndwdrag이 뭘까? [`-gestureForFailureRelationships`](https://developer.apple.com/documentation/uikit/uiwindowscenedraginteraction/4200083-gestureforfailurerelationships)은 아래와 같은데

```
<_UIRelationshipGestureRecognizer: 0x105e1c010 (UIWindowSceneDragRelationshipRecognizer); state = Possible; view = <UIView: 0x105e11cf0>>
```

UIWindowSceneDragRelationshipRecognizer의 약자인가? SpringBoard는 `_UIRelationshipGestureRecognizer`와 통신하는건가? SpringBoard를 Reverse Engineering해야 답이 나올듯...

내부적인 UIPanGestureRecognizer들은 wndwpan을 가진다.

아마 UIPanGestureRecognizer -> UIWindowSceneDragRelationshipRecognizer -> SpringBoard인듯?
