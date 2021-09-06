# Swift의 AnyObject에 대해

`Any`와 `AnyObject`의 차이점을 설명해 보라고 하면, `Any`는 모든 Type에 적용할 수 있고, `AnyObject`는 Class Type에만 적용할 수 있습니다. 또 하나 차이점이 있는데요. `AnyObject`는 Objective-C Selector 전송을 지원합니다.

예시를 들어봅시다. 아래와 같은 Objective-C Object가 있다고 가정합시다.

```objective-c
//  MyViewController.h

#import <Cocoa/Cocoa.h>

NS_SWIFT_UI_ACTOR
@interface MyViewController : NSViewController
- (void)sayHi;
@end
```

```objective-c
#import "MyViewController.h"

@implementation MyViewController
- (void)sayHi {
    NSLog(@"Hi!!!");
}
@end
```

그러면 Swift의 AnyObject에서 아래와 같이 Selector 전송을 지원합니다.

```swift
let object: AnyObject = MyViewController()
let value: Void = object.sayHi()
```

## 하지만 이러면 빌드가 오래 걸린다.

... 이 이유를 설명하기 위해, Selector을 호출할 때 return 타입 추측과 메모리 관리를 어떻게 하는지 적어볼게요. 일단 Objective-C Memory Management 규칙은 간단하게 아래와 같습니다.

- method에서 return 되는 object는 autorelease 상태여야 합니다. (new, init, copy, mutableCopy 등은 retain)
- return 값에서 나오는 object는 retain해서 다뤄야 한다. 또한, 나중에 release/autorelease를 반드시 호출해야 한다. 

자, 이제 Objective-C ARC를 꺼보고, Objective-C 상에서 String Literal로 `sayHi` Selector를 실행해 볼게요.

```objective-c
MyViewController *object = [MyViewController new];
[object performSelector:NSSelectorFromString(@"sayHi")];
[object release];
```

이러면 별다른 error나 warning 없이 잘 실행됩니다. 이제, ARC를 켜볼게요. 그러면 아래와 같은 warning이 뜨네요.

```
PerformSelector may cause a leak because its selector is unknown
```

이 이유는 selector perform하면 컴파일러는 return 타입을 무조건  `id`  타입으로 추측하고 (설령 예시처럼 return 타입이 `void`이어도, `id`로 추측해 버립니다.), 또한 **ARC는 retain이나 release/autorelease를 하지 않습니다**. 만약 selector에서 autorelease 예정이 아닌, retain 상태인 object를 return 한다면? 그러면 ARC에서 memory leak이 발생하는거죠. 그래서 저런 warning이 뜨는거에요. 이거는 unknown selector, known Selector 모두 마찬가지에요.

그러면 컴파일러는 왜 selector의 return 타입을 무조건 `id`로 추측해 버리고, ARC는 메모리 관리를 안해줄까요? 이 이유는 unknown selector 때문입니다. unknown selector는 프로젝트 내에서 모든 NSObject methods의 header 파일에서 정의되지 않은 method이기 때문에, 컴파일러는 return 타입을 알 수 없어서 무조건 `id`로 해버리는 겁니다. ARC도 return 타입이 object인지 알 수 없기 때문에 메모리 관리를 함부로 못하는 거고요.

(Objective-C에서 known selector에 대해 좀 설명을 하자면, known selector는 프로젝트 내에서 정의된 **모든 NSObject methods**를 뜻합니다. object 자기 자신만의 method만을 known selector라고 하지 않아요. 만약에, `MyViewController`에서 전혀 관련 없는 NSNumber의 [compare:](https://developer.apple.com/documentation/foundation/nsnumber/1413562-compare) selector를 실행해도 빌드에서는 아무런 error나 warning이 뜨지 않아요. 런타임에서 에러가 나죠.)

### 그래서 Swift에서 빌드가 왜 오래 걸리는지

위에서 말씀드렸듯이, Objective-C에서 Selector를 실행할 경우

- return 타입은 무조건 `id`로 쳐버립니다.

- ARC는 메모리 관리를 하지 않습니다.

이런 문제점이 있는거고, Swift의 AnyObject에서 Selector 실행에는 이런 문제들이 없습니다. 이를 위해 Swift는 프로젝트 내에서 정의된 모든  NSObject의 method를 dispatch하고 return type을 명확하게 가져오고, 메모리 관리를 해줍니다.

... 이 말을 들으시면 컴파일러가 AnyObject에서 method 실행을 위해 많은 컴파일 시간을 투자해야 한다는게 감이 오실거에요.

```swift
let object: AnyObject = MyViewController()
        
let value1: Void = object.sayHi()
print(value1) // ()

// NSNumber.compare(_:)
let value3: ComparisonResult = object.compare(NSNumber(integerLiteral: 0)) // 런타임 에러! -[MyViewController compare:]: unrecognized selector sent to instance

let value2: Unmanaged<AnyObject>? = object.perform(#selector(MyViewController.sayHi))
print(value2) // 런타임 에러! EXC_BAD_ACCESS
```

## 출처

[Swift regret: AnyObject method dispatch](https://twitter.com/UINT_MIN/status/1430652663662735362)

