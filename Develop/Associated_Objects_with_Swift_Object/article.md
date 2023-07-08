# Swift Object로 Associated Object 써보기

Objective-C에서 Associated Object는 Object에 Key-Value로 값을 저장하고 읽을 수 있게 해줍니다.

이는 NSObject만 지원하며, 아래처럼 Swift Object에서는 지원하지 않습니다.

```swift
import Foundation

actor MyObject {
    
}

let object: MyObject = .init()
let p: UnsafeMutablePointer<UInt8> = .allocate(capacity: 1)

// Runtime ERROR: objc[75001]: objc_setAssociatedObject called on instance (0x600002834000) of class Ass.MyObject which does not allow associated objects
objc_setAssociatedObject(object, p, nil, .OBJC_ASSOCIATION_ASSIGN)

p.deallocate()
```

이 글에서는 NSObject를 subclassing하지 않으면서 위 코드가 되게 하는 방법을 소개합니다.

arm64e assembly로 설명합니다.

## 왜 크래시가 나는지

- [`objc_setAssociatedObject`](https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-runtime.mm#L720)는 [`_object_set_associative_reference`](https://github.com/apple-oss-distributions/objc4/blob/c3f002513d195ef564f3c7e9496c2606360e144a/runtime/objc-references.mm#L160)를 호출합니다.

- `_object_set_associative_reference`에서 [이 부분](https://github.com/apple-oss-distributions/objc4/blob/c3f002513d195ef564f3c7e9496c2606360e144a/runtime/objc-references.mm#L167)을 보면

    ```objc
    if (object->getIsa()->forbidsAssociatedObjects())
        _objc_fatal("objc_setAssociatedObject called on instance (%p) of class %s which does not allow associated objects", object, object_getClassName(object));
    ```

    object의 Class (`getIsa`)의 forbidsAssociatedObjects()을 확인해서 associated object가 금지되어 있을 경우 크래시가 납니다.
    
이런 과정으로 크래시가 납니다.

참고로 Swift class가 Objective-C Runtime에 넘어가게 되면 Swift class는 [`SwiftObject`](https://github.com/apple/swift/blob/a682358a2954a413074bf72bb980068b9eec1941/stdlib/public/runtime/SwiftObject.h#L41)라는 Objective-C class 객체로 wrap됩니다. 하지만 이 객체는 `NSObject`를 subclassing하지 않고 있습니다. 또한 객체가 아닌건 아마 `__SwiftValue`였던 걸로 기억하는데 가물가물하고 이 글이랑 관련 없는 내용

## 크래시 피하기 (1)

- [`forbidsAssociatedObjects()`](https://github.com/apple-oss-distributions/objc4/blob/c3f002513d195ef564f3c7e9496c2606360e144a/runtime/objc-runtime-new.h#L2589)은 flags에서 `RW_FORBIDS_ASSOCIATED_OBJECTS` (`1<<20 = 0x100000`) 값과 collision이 있을 경우에 true를 반환합니다.

- 따라서 Class의 flags를 건드리면 `forbidsAssociatedObjects()`에서 false가 반환될 것 같고, 그러면 크래시를 피할 수 있을 것 같네요.

- flag에 `RW_FORBIDS_ASSOCIATED_OBJECTS`을 기록하는 것은 Runtime의 `realizeClassWithoutSwift`에서 처리되고 있습니다. [링크](https://github.com/apple-oss-distributions/objc4/blob/c3f002513d195ef564f3c7e9496c2606360e144a/runtime/objc-runtime-new.mm#L2724)

    ```objc
    // Propagate the associated objects forbidden flag from ro or from
    // the superclass.
    if ((ro->flags & RO_FORBIDS_ASSOCIATED_OBJECTS) ||
        (supercls && supercls->forbidsAssociatedObjects()))
    {
        rw->flags |= RW_FORBIDS_ASSOCIATED_OBJECTS;
    }
    ```

- `realizeClassWithoutSwift`의 메모리 주소는 `0x00000001825e5074`라고 뜨는데

    ```
    (lldb) image lookup -vn _ZL24realizeClassWithoutSwiftP10objc_classS0_
    1 match found in /usr/lib/libobjc.A.dylib:
            Address: libobjc.A.dylib[0x000000018006d074] (libobjc.A.dylib.__TEXT.__text + 13428)
            Summary: libobjc.A.dylib`realizeClassWithoutSwift(objc_class*, objc_class*)
             Module: file = "/usr/lib/libobjc.A.dylib", arch = "arm64e"
             Symbol: id = {0x00000013}, range = [0x00000001825e5074-0x00000001825e5e34), name="realizeClassWithoutSwift(objc_class*, objc_class*)", mangled="_ZL24realizeClassWithoutSwiftP10objc_classS0_"
    ```

    assembly를 보면 위 코드는 아래와 같습니다.
    
    ```
    0x1825e56b0 <+1596>: ldseth w8, w8, [x9]
    0x1825e56b4 <+1600>: ldr    w8, [x23]
    0x1825e56b8 <+1604>: tbnz   w8, #0xa, 0x1825e5708     ; <+1684>
    0x1825e56bc <+1608>: cbz    x24, 0x1825e5764          ; <+1776>
    0x1825e56c0 <+1612>: mov    x8, x24
    0x1825e56c4 <+1616>: ldr    x16, [x8, #0x20]!
    0x1825e56c8 <+1620>: mov    x17, x8
    0x1825e56cc <+1624>: movk   x17, #0xc93a, lsl #48
    0x1825e56d0 <+1628>: autdb  x16, x17
    0x1825e56d4 <+1632>: mov    x17, x16
    0x1825e56d8 <+1636>: xpacd  x17
    0x1825e56dc <+1640>: cmp    x16, x17
    0x1825e56e0 <+1644>: b.eq   0x1825e56e8               ; <+1652>
    0x1825e56e4 <+1648>: brk    #0xc473
    0x1825e56e8 <+1652>: and    x8, x16, x20
    0x1825e56ec <+1656>: ldrb   w8, [x8, #0x2]
    0x1825e56f0 <+1660>: tbz    w8, #0x4, 0x1825e571c     ; <+1704>
    0x1825e56f4 <+1664>: ldr    x9, [sp, #0x48]
    0x1825e56f8 <+1668>: ldr    w8, [x9]
    0x1825e56fc <+1672>: orr    w8, w8, #0x100000
    0x1825e5700 <+1676>: str    w8, [x9]
    0x1825e5704 <+1680>: b      0x1825e571c               ; <+1704>
    0x1825e5708 <+1684>: ldr    x9, [sp, #0x48]
    0x1825e570c <+1688>: ldr    w8, [x9]
    0x1825e5710 <+1692>: orr    w8, w8, #0x100000
    0x1825e5714 <+1696>: str    w8, [x9]
    ```

    `<+1684>`와 `<+1660>`의 `w8` register에 둘다 `0x0`을 주입해주면 `orr    w8, w8, #0x100000`을 막을 수 있고, 이는 flag에 `RW_FORBIDS_ASSOCIATED_OBJECTS`이 주입되는 것을 막을 수 있게 됩니다.
    
    ```
    (lldb) breakpoint set -a 0x1825e56b8 -G1 -C 'register write w8 0x0'
    Breakpoint 9: where = libobjc.A.dylib`realizeClassWithoutSwift(objc_class*, objc_class*) + 1604, address = 0x00000001825e56b8
    (lldb) breakpoint set -a 0x1825e56f0 -G1 -C 'register write w8 0x0'
    Breakpoint 10: where = libobjc.A.dylib`realizeClassWithoutSwift(objc_class*, objc_class*) + 1660, address = 0x00000001825e56f0
    ```
    
이렇게 하니 잘 되네요.
    
## 크래시 피하기 (2)

아까 위에서 보여드렸던 `objc_setAssociatedObject`의 코드 중

```objc
if (object->getIsa()->forbidsAssociatedObjects())
    _objc_fatal("objc_setAssociatedObject called on instance (%p) of class %s which does not allow associated objects", object, object_getClassName(object));
```

위 코드를 무력화시키면 됩니다. 위 코드는 assembly에서는 아래와 같기에

```
0x1825f56d4 <+312>:  tbnz   w8, #0x4, 0x1825f5b14     ; <+1400>

# <+1400>으로 jump

0x1825f5b14 <+1400>: mov    x0, x19
0x1825f5b18 <+1404>: bl     0x1825f4060               ; object_getClassName
0x1825f5b1c <+1408>: stp    x19, x0, [sp]
0x1825f5b20 <+1412>: adrp   x0, 54
0x1825f5b24 <+1416>: add    x0, x0, #0xea             ; "objc_setAssociatedObject called on instance (%p) of class %s which does not allow associated objects"
0x1825f5b28 <+1420>: bl     0x18261d398               ; _objc_fatal(char const*, ...)
```

`<+312>`에서 `w8` register에 `0x0`을 주입해주면 마찬가지로 잘 되나... 이건 `objc_setAssociatedObject`이 호출될 때마다 register 값을 바꾸는거라 성능에 안 좋아요.

처음에 소개드린 방법이 dyld load 시점이 되는거라 최초 한 번만 수행되기에 성능에 더 좋습니다.

## Memory Leak

### NSObject에서는?

NSObject에서는 `-[NSObject dealloc]`이 불릴 때 모든 associated objects들을 release 시킵니다. 이 원리는

- [`-[NSObject dealloc]`](https://github.com/gnustep/libs-base/blob/c6df659d35cdab94362bfa7d158f1069ac12e4f0/Source/NSObject.m#L1373)은 [`NSDeallocateObject`](https://github.com/gnustep/libs-base/blob/c6df659d35cdab94362bfa7d158f1069ac12e4f0/Source/NSObject.m#L825C1-L825C32)을 호출함

- `NSDeallocateObject`은 [`object_dispose`](https://github.com/apple-oss-distributions/objc4/blob/c3f002513d195ef564f3c7e9496c2606360e144a/runtime/objc-runtime-new.mm#L8643)를 호출함

- `object_dispose`은 [`objc_destructInstance`](https://github.com/apple-oss-distributions/objc4/blob/c3f002513d195ef564f3c7e9496c2606360e144a/runtime/objc-runtime-new.mm#L8620)를 호출함

- `objc_destructInstance`은 `_object_remove_associations`를 호출하면서 자신이 들고 있는 모든 assosicated objects들을 release 시킴

따라서 NSObject에서는 `-dealloc`만 잘 호출된다면 associated objects들은 leak을 발생시키지 않습니다.

### SwiftObject에서는

SwiftObject는 associated object를 지원하지 않기에 위 NSObject와 같은 로직이 없습니다. 따라서 위 방법대로 SwiftObject에서 associated object를 강제로 설정한다면 leak이 발생합니다.
 
'SwiftObject의 dealloc을 swizzling하면 되는거 아니야?' 라는 생각을 할 수 있는데, `dealloc`은 Objective-C class에 종속된게 아닌, `-[NSObject dealloc]`의 기능입니다. 따라서 SwiftObject에는 `-dealloc`이 존재하지 않습니다.

대신 [`swift::swift_unknownObjectRelease_n`](https://github.com/apple/swift/blob/a682358a2954a413074bf72bb980068b9eec1941/stdlib/public/runtime/SwiftObject.mm#L497)와 [`swift::swift_unknownObjectRelease`](https://github.com/apple/swift/blob/a682358a2954a413074bf72bb980068b9eec1941/stdlib/public/runtime/SwiftObject.mm#L513)이 존재합니다. 내부에 `objc_release`를 호출하는 것을 보실 수 있습니다. 아마 `objc_release`에서 retain count가 0일 경우 메모리를 비워줄 것 같네요.

따라서 memory leak을 해결하려면

- 저 함수들이 호출될 때 [`-[_TtCs12_SwiftObject retainCount]`](https://github.com/apple/swift/blob/a682358a2954a413074bf72bb980068b9eec1941/stdlib/public/runtime/SwiftObject.h#L74)를 검사하고, 0일 경우 [`objc_removeAssociatedObjects`](https://developer.apple.com/documentation/objectivec/1418683-objc_removeassociatedobjects)을 호출하거나

- [`-[_TtCs12_SwiftObject release]`](https://github.com/apple/swift/blob/a682358a2954a413074bf72bb980068b9eec1941/stdlib/public/runtime/SwiftObject.h#L72)가 호출될 때 retainCount가 0일 경우 [`objc_removeAssociatedObjects`](https://developer.apple.com/documentation/objectivec/1418683-objc_removeassociatedobjects)을 호출

이런 방법들이 있을 것 같은데 해보진 않음...

## 이런거 하는 이유

SwiftData의 내부 버그 때문

SwiftData의 내부에서 `SwiftObject`를 `objc_setAssociatedObject`에 넣어서 크래시나는 이슈가 있었고 이를 해결하기 위해 이짓거리를 했어요.

참고 : [SwiftData에서 ModelActor 사용하기](https://github.com/pookjw/pookjw.github.io/blob/main/Develop/SwiftData_ModelActor/article.md)
