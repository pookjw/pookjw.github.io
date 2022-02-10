# Swift로 정의된 NSObject 객체의 이름에 대해

저희는 iOS 개발을 할 때 Swift로 통해 `UIViewController`, `UIView` 같은 `NSObject` 기반 객체를 생성하고 있습니다. 이러한 코드는 컴파일이 될 때 Objective-C로 Bridging하는 과정이 있는데, 이 과정에서 객체 이름이 어떻게 정해지는지에 대해 설명드리려고 합니다.

## 실험

Xcode에서 `SampleApp`이라는  샘플 iOS 앱을 하나 만들어서, 아래와 같은 `ViewController`를 만들어 봤습니다.

```swift
class ViewController: UIViewController {
}
```

빌드해서 생성된 바이너리 파일을 [Hopper](https://www.hopperapp.com)로 통해 살펴보면, `ViewController`가 아래와 같이 Objectjve-C 상에서 Bridging되는 코드가 생성된걸 확인할 수 있습니다. 보시면 객체 이름이 `ViewController`가 아닌, `_TtC9SampleApp14ViewController`로 정의되어 있습니다.

```assembly
                             ; 
                             ; @metaclass _TtC9SampleApp14ViewController  {
                             ; }
                     _OBJC_METACLASS_$__TtC9SampleApp14ViewController:
000000010000d988         struct __objc_class {                                  ; DATA XREF=_$s9SampleApp14ViewControllerCN
                             _OBJC_METACLASS_$_NSObject,          // metaclass
                             _OBJC_METACLASS_$_UIViewController,  // superclass
                             __objc_empty_cache,                  // cache
                             0x0,                                 // vtable
                             __METACLASS_DATA__TtC9SampleApp14ViewController // data
```

한 번 Objective-C Runtime 함수로 실험을 해봅시다. Objective-C Bridging Header를 만들어서 아래와 같이 정의하고

```objc
#import <objc/runtime.h>
```

`ViewController.viewDidLoad()`에서 아래와 같은 실험 코드를 넣어보고 돌려봅시다.

```swift
class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let class1: AnyClass? = NSClassFromString("ViewController")
        let class2: AnyClass? = NSClassFromString("_TtC9SampleApp14ViewController")
        
        print(class1, class2)
    }
}
```

그러면 콘솔창에 아래와 같은 결과가 나옵니다. 런타임 상에서 `ViewController`는 존재하지 않고, `_TtC9SampleApp14ViewController`만 존재한다는걸 알 수 있습니다.

```
nil Optional(SampleApp.ViewController)
```

또 다른 실험을 해봅시다. `ViewController`를 정의한 부분에서 `@objc(ViewController)` 키워드를 사용해 보겠습니다.

```swift
@objc(ViewController)
class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let class1: AnyClass? = NSClassFromString("ViewController")
        let class2: AnyClass? = NSClassFromString("_TtC9SampleApp14ViewController")
        
        print(class1, class2)
    }
}
```

다시 빌드해보고 다시 Hopper로 살펴보면, `_TtC9SampleApp14ViewController`는 더 이상 존재하지 않고, `ViewController`로 이름이 제대로 정의된 것을 볼 수 있습니다.

```assembly
                     __METACLASS_DATA_ViewController:
0000000100010000         struct __objc_data {                                   ; "ViewController", DATA XREF=_$s9SampleApp14ViewControllerC11viewDidLoadyyF+80, _$s9SampleApp14ViewControllerC7nibName6bundleACSSSg_So8NSBundleCSgtcfC+128, _$s9SampleApp14ViewControllerC7nibName6bundleACSSSg_So8NSBundleCSgtcfc+196, _$s9SampleApp14ViewControllerC5coderACSgSo7NSCoderC_tcfC+28, _$s9SampleApp14ViewControllerC5coderACSgSo7NSCoderC_tcfc+72, _$s9SampleApp14ViewControllerCfD+44, _$s9SampleApp0B8DelegateC11application_26configurationForConnecting7optionsSo20UISceneConfigurationCSo13UIApplicationC_So0I7SessionCSo0I17ConnectionOptionsCtF+108, _$sSo20UISceneConfigurationCMa+32, _$sSo14UISceneSessionCMa+32, _$s9SampleApp0B8DelegateCACycfC+16, _$s9SampleApp0B8DelegateCACycfc+56
                             0x81,                                // flags
                             40,                                  // instance start
                             40,                                  // instance size
                             0x0,
                             0x0,                                 // ivar layout
                             aViewcontroller,                     // name
                             0x0,                                 // base methods
                             0x0,                                 // base protocols
                             0x0,                                 // ivars
                             0x0,                                 // weak ivar layout
                             0x0                                  // base properties
                         }
```

하지만 `viewDidLoad()`에서 찍히는 콘솔에서는 여전히 `_TtC9SampleApp14ViewController`는 존재한다고 뜹니다.

```
Optional(SampleApp.ViewController) Optional(SampleApp.ViewController)
```

## 궁금증

위 실험 결과를 통해 아래와 같은 궁금증이 생깁니다.

1. 왜 `ViewController`라는 객체는 `_TtC9SampleApp14ViewController`라는 이름으로 바뀌는 것인가?
2. `_TtC9SampleApp14ViewController`라는 이름은 무슨 규칙으로 생성되는걸까?
3. `@objc(ViewController)`로 객체 이름을 정의해줬고 Hopper로 `_TtC9SampleApp14ViewController`는 더 이상 존재하지 않는 것을 확인했는데도 불구하고, 왜 `viewDidLoad()`에서는 `_TtC9SampleApp14ViewController`가 존재하는 것으로 찍히는걸까?

### 1번

1번에 대한 답변은 제 뇌피셜이긴 한데요. Swift는 namespace를 내부적으로 지원합니다. 제가 `First.swift`랑 `Second.swift` 파일 2개를 만들어서, 파일 2개 똑같이 아래와 같이 코드를 적어봤습니다.

```swift
import Foundation

private class SampleObject: NSObject {
}
```

이렇게 되면 `SampleObject`가 2개 정의되어 있게 됩니다. 빌드에도 문제가 없습니다. Objective-C는 namespace를 지원하지 않아, symbol이 겹치면 안 되기 때문에 위와 같은 코드는 빌드에 에러가 나지만, Swift는 namespace를 지원하기 때문에 빌드에 문제가 없습니다.

그러면 Hopper에서 2개의 `SampleObject`가 어떻게 정의되었는지 살펴봅시다.

```assembly
                             ; 
                             ; @metaclass __TtC9SampleAppP33_457EECDA3EE0E77D6D590CB76766B48312SampleObject  {
                             ; }
                     _OBJC_METACLASS_$__TtC9SampleAppP33_457EECDA3EE0E77D6D590CB76766B48312SampleObject:
0000000100011c18         struct __objc_class {                                  ; DATA XREF=_OBJC_CLASS_$__TtC9SampleAppP33_457EECDA3EE0E77D6D590CB76766B48312SampleObject
                             _OBJC_METACLASS_$_NSObject,          // metaclass
                             _OBJC_METACLASS_$_NSObject,          // superclass
                             __objc_empty_cache,                  // cache
                             0x0,                                 // vtable
                             __METACLASS_DATA__TtC9SampleAppP33_457EECDA3EE0E77D6D590CB76766B48312SampleObject // data
                         }
                             ; 
                             ; @metaclass _TtC9SampleAppP33_ADC5A0CFF388A6BE328B08EA8E4A462212SampleObject  {
                             ; }
                     _OBJC_METACLASS_$__TtC9SampleAppP33_ADC5A0CFF388A6BE328B08EA8E4A462212SampleObject:
0000000100011c40         struct __objc_class {                                  ; DATA XREF=_OBJC_CLASS_$__TtC9SampleAppP33_ADC5A0CFF388A6BE328B08EA8E4A462212SampleObject
                             _OBJC_METACLASS_$_NSObject,          // metaclass
                             _OBJC_METACLASS_$_NSObject,          // superclass
                             __objc_empty_cache,                  // cache
                             0x0,                                 // vtable
                             __METACLASS_DATA__TtC9SampleAppP33_ADC5A0CFF388A6BE328B08EA8E4A462212SampleObject // data
                         }
```

두개의 `SampleObject`가 각각 `__TtC9SampleAppP33_457EECDA3EE0E77D6D590CB76766B48312SampleObject`와 `__TtC9SampleAppP33_ADC5A0CFF388A6BE328B08EA8E4A462212SampleObject`로 정의된 것을 볼 수 있습니다.

이런 식으로  namespace 지원때문에, Swift 컴파일러는 객체의 이름을 건드리는 구조입니다. 다만 Objective-C Bridging이 필요해서 이런 과정을 없애고 싶다면, `@objc(className)` 키워드를 쓰면 되는 것이지요.

### 2번

2번의 대한 답은 애플이 공개한 [dyld](https://github.com/apple-oss-distributions/dyld) 소스코드의 [OptimizerObjC.cpp](https://github.com/apple-oss-distributions/dyld/blob/9a9e3e4cfa7de205d61f4114c9b564e4bab7ef7f/cache-builder/OptimizerObjC.cpp#L75)에서 찾을 수 있습니다. 이 파일에는 아래와 같은 코드가 있습니다.

```cpp
static char *copySwiftDemangledName(const char *string, bool isProtocol = false)
{
    if (!string) return nullptr;

    // Swift mangling prefix.
    if (strncmp(string, isProtocol ? "_TtP" : "_TtC", 4) != 0) return nullptr;
    string += 4;

    const char *end = string + strlen(string);

    // Module name.
    const char *prefix;
    int prefixLength;
    if (string[0] == 's') {
        // "s" is the Swift module.
        prefix = "Swift";
        prefixLength = 5;
        string += 1;
    } else {
        if (! scanMangledField(string, end, prefix, prefixLength)) return nullptr;
    }

    // Class or protocol name.
    const char *suffix;
    int suffixLength;
    if (! scanMangledField(string, end, suffix, suffixLength)) return nullptr;

    if (isProtocol) {
        // Remainder must be "_".
        if (strcmp(string, "_") != 0) return nullptr;
    } else {
        // Remainder must be empty.
        if (string != end) return nullptr;
    }

    char *result;
    asprintf(&result, "%.*s.%.*s", prefixLength,prefix, suffixLength,suffix);
    return result;
}
```

위 코드를 말로 풀어쓰면

1. Swift로 정의된 객체에는 이름에 `_TtC`, 프로토콜에는 `_TtP`라는 prefix가 추가됩니다.
2. 만약 prefix가 `s`로 시작될 경우에는 Swift module로 인식합니다. (Hopper에서 구조를 자세히 보시면 이런 것들이 보입니다. 예를 들면 `swift_getObjCClassMetadata`)
3. module 이름의 자릿수 + 객체/프로토콜 이름의 자릿수를 객체 이름에 넣어줍니다.

예를 들어, `SampleApp`의 `ViewController` 객체는

1. 객체이니까 `_TtC`
2. module 이름은 `SampleApp` - 9글자
3. 객체 이름인 `ViewController` - 14글자
4. 결론 : `_TtC9SampleApp14ViewController`

이렇게 됩니다.

### 3번

`NSClassFromString(_:)`를 호출하게 될 경우 2번에서 언급한 로직을 타도록 되어 있습니다. 따라서 Hopper 상에서 `_TtC9SampleApp14ViewController`가 정의되지 않았어도, 위 로직을 통해 `SampleApp.ViewController`로 강제 변환되기 때문에, `NSClassFromString("_TtC9SampleApp14ViewController")`을 호출해도 nonnull 값이 나옵니다.
