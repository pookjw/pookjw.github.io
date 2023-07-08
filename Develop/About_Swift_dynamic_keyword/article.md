# Swift의 dynamic 키워드에 대해

옛날에 RealmSwift를 써본 사람이라면 `dynamic` 키워드에 익숙할 것이다. Swift 공부를 하다보면 한 번쯤은 관심을 가졌을 것 같다.

[The Swift Programming Language](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/declarations/)에서는 아래와 같이 설명한다.

> Apply this modifier to any member of a class that can be represented by Objective-C. When you mark a member declaration with the dynamic modifier, access to that member is always dynamically dispatched using the Objective-C runtime. Access to that member is never inlined or devirtualized by the compiler.
> Because declarations marked with the dynamic modifier are dispatched using the Objective-C runtime, they must be marked with the objc attribute.

요약하면 Objective-C class에서 쓰면 Objective-C Runtime로 dispatch 된다... 한 마디로 `text`, `setText:` 같은 getter/setter를 항상 호출한다는 뜻이다. 덕분에 KVO도 된다.

하지만 위 설명에서는 Swift class에 적으면 어떻게 되는지에 대한 설명이 누락되어 있다. `dynamic` 키워드는 Objective-C class에서만 쓸 수 있는게 아니다. 아래처럼 NSObject나 `@objc`가 아니어도 쓸 수 있다.

```swift
class Foo {
    dynamic var text: String?
}
```

이 글에서는 Objective-C class, Swift class에서 dynamic 키워드가 어떻게 동작하는지 살펴본다.

## Objective-C class에서

아래처럼 `Foo`라는 NSObject가 있다고 가정하자. `dynamic` 키워드가 없는 것을 볼 수 있다.

```swift
@objc(Foo) class Foo: NSObject {
    @objc var text: NSString?
}
```

그러면 아래와 같은 metadata가 생성된다. `text` property에 `@objc`를 명시해 놨기에 `-text`, `-setText:` 같은 getter/setter가 잘 생성된 것을 볼 수 있다. 참고로 `dynamic` 유무에 상관 없이 아래와 같은 metadata가 만들어진다.

```
(lldb) expression -l objc -O -- [Foo _shortMethodDescription]
<Foo: 0x1045d03d8>:
in Foo:
    Properties:
        @property (nonatomic, retain) NSString* text;  (@synthesize text = text;)
    Instance Methods:
        - (id) text; (0x1045c7f00)
        - (void) setText:(id)arg1; (0x1045c7fac)
        - (id) init; (0x1045c82d4)
        - (void) .cxx_destruct; (0x1045c833c)
(NSObject ...)
```

한 번 `-setText:`에 breakpoint를 걸어보자

```
(lldb) breakpoint set -a 0x104bec034
Breakpoint 2: where = MiscellaneousObservation`@objc MiscellaneousObservation.Foo.text.setter : Swift.Optional<__C.NSString> at <compiler-generated>, address = 0x0000000104bec034
```

그리고 KVC으로 `-setText:`를 발동시키면 breakpoint로 인해 pause가 잘 걸리는 것을 확인할 수 있다.

```swift
let foo: Foo = .init()
foo.setValue("TEST", forKey: #keyPath(Foo.text))
```

```
MiscellaneousObservation`@objc Foo.text.setter:
->  0x104fd0034 <+0>:  sub    sp, sp, #0x30
    0x104fd0038 <+4>:  stp    x20, x19, [sp, #0x10]
    0x104fd003c <+8>:  stp    x29, x30, [sp, #0x20]
    0x104fd0040 <+12>: add    x29, sp, #0x20
    0x104fd0044 <+16>: mov    x20, x0
    0x104fd0048 <+20>: str    x20, [sp, #0x8]
    0x104fd004c <+24>: mov    x0, x2
    0x104fd0050 <+28>: str    x0, [sp]
    0x104fd0054 <+32>: bl     0x104fd27b0               ; symbol stub for: objc_retain
    0x104fd0058 <+36>: mov    x0, x20
    0x104fd005c <+40>: bl     0x104fd27b0               ; symbol stub for: objc_retain
    0x104fd0060 <+44>: ldr    x0, [sp]
    0x104fd0064 <+48>: bl     0x104fd0080               ; MiscellaneousObservation.Foo.text.setter : Swift.Optional<__C.NSString> at ContentView.swift:12
    0x104fd0068 <+52>: ldr    x0, [sp, #0x8]
    0x104fd006c <+56>: bl     0x104fd2798               ; symbol stub for: objc_release
    0x104fd0070 <+60>: ldp    x29, x30, [sp, #0x20]
    0x104fd0074 <+64>: ldp    x20, x19, [sp, #0x10]
    0x104fd0078 <+68>: add    sp, sp, #0x30
    0x104fd007c <+72>: ret    
```

또한 Swift에서 아래와 같은 코드를 호출해보자

```swift
let foo: Foo = .init()
foo.text = "BOO!"
```

breakpoint에 의한 pause가 안 걸린다. `-setText:`가 안 불린다는 뜻이다. 한 번 `text`에 watchpoint를 걸어보면 아래처럼 `Foo.text.setter:`에서 pause가 걸린다.

이는 `foo.text = "BOO!"`를 호출하면 Swift Runtime 코드만 돌아가며 Objective-C Runtime이 호출하지 않는 것을 알 수 있다. 아래 코드만 봐도 `objc_msgSnd`을 통한 `-setText:` 호출될만한 코드는 없어 보이기 때문이다.

```
MiscellaneousObservation`Foo.text.setter:
    0x1045c7ff8 <+0>:   sub    sp, sp, #0x50
    0x1045c7ffc <+4>:   stp    x29, x30, [sp, #0x40]
    0x1045c8000 <+8>:   add    x29, sp, #0x40
    0x1045c8004 <+12>:  str    x0, [sp, #0x10]
    0x1045c8008 <+16>:  stur   xzr, [x29, #-0x8]
    0x1045c800c <+20>:  stur   xzr, [x29, #-0x10]
    0x1045c8010 <+24>:  stur   x0, [x29, #-0x8]
    0x1045c8014 <+28>:  stur   x20, [x29, #-0x10]
    0x1045c8018 <+32>:  bl     0x1045ca7a4               ; symbol stub for: objc_retain
    0x1045c801c <+36>:  adrp   x8, 8
    0x1045c8020 <+40>:  ldr    x8, [x8, #0x488]
    0x1045c8024 <+44>:  add    x0, x20, x8
    0x1045c8028 <+48>:  str    x0, [sp]
    0x1045c802c <+52>:  add    x1, sp, #0x18
    0x1045c8030 <+56>:  str    x1, [sp, #0x8]
    0x1045c8034 <+60>:  mov    w8, #0x21
    0x1045c8038 <+64>:  mov    x2, x8
    0x1045c803c <+68>:  mov    x3, #0x0
    0x1045c8040 <+72>:  bl     0x1045ca8dc               ; symbol stub for: swift_beginAccess
    0x1045c8044 <+76>:  ldr    x9, [sp]
    0x1045c8048 <+80>:  ldr    x8, [sp, #0x10]
    0x1045c804c <+84>:  ldr    x0, [x9]
    0x1045c8050 <+88>:  str    x8, [x9]
->  0x1045c8054 <+92>:  bl     0x1045ca78c               ; symbol stub for: objc_release
    0x1045c8058 <+96>:  ldr    x0, [sp, #0x8]
    0x1045c805c <+100>: bl     0x1045caa98               ; symbol stub for: swift_endAccess
    0x1045c8060 <+104>: ldr    x0, [sp, #0x10]
    0x1045c8064 <+108>: bl     0x1045ca78c               ; symbol stub for: objc_release
    0x1045c8068 <+112>: ldp    x29, x30, [sp, #0x40]
    0x1045c806c <+116>: add    sp, sp, #0x50
    0x1045c8070 <+120>: ret    
```

이제 한 번 `dynamic` 키워드를 붙여보자

```swift
@objc(Foo) class Foo: NSObject {
    @objc dynamic var text: NSString?
}

let foo: Foo = .init()
foo.text = "BOO!"
```

그러면 `-setText:`에서 pause가 걸린다. 문서대로 Objective-C Runtime에서 dispatch가 먼저 발동하며, `<+48>`에서 Swift Runtime으로 넘어간다.

```
MiscellaneousObservation`@objc Foo.text.setter:
->  0x1006500e8 <+0>:  sub    sp, sp, #0x30
    0x1006500ec <+4>:  stp    x20, x19, [sp, #0x10]
    0x1006500f0 <+8>:  stp    x29, x30, [sp, #0x20]
    0x1006500f4 <+12>: add    x29, sp, #0x20
    0x1006500f8 <+16>: mov    x20, x0
    0x1006500fc <+20>: str    x20, [sp, #0x8]
    0x100650100 <+24>: mov    x0, x2
    0x100650104 <+28>: str    x0, [sp]
    0x100650108 <+32>: bl     0x1006527c4               ; symbol stub for: objc_retain
    0x10065010c <+36>: mov    x0, x20
    0x100650110 <+40>: bl     0x1006527c4               ; symbol stub for: objc_retain
    0x100650114 <+44>: ldr    x0, [sp]
    0x100650118 <+48>: bl     0x100650134               ; MiscellaneousObservation.Foo.text.setter : Swift.Optional<__C.NSString> at ContentView.swift:12
    0x10065011c <+52>: ldr    x0, [sp, #0x8]
    0x100650120 <+56>: bl     0x1006527ac               ; symbol stub for: objc_release
    0x100650124 <+60>: ldp    x29, x30, [sp, #0x20]
    0x100650128 <+64>: ldp    x20, x19, [sp, #0x10]
    0x10065012c <+68>: add    sp, sp, #0x30
    0x100650130 <+72>: ret    

```

### KVO

`dynamic` 키워드를 적으면 Swift 코드에서 setter를 발동시킬 때 KVO이 된다.

```swift
import Foundation

@objc(Foo) class Foo: NSObject {
    @objc var text: NSString? {
        willSet {
            willChangeValue(forKey: #keyPath(Foo.text))
        }
        didSet {
            didChangeValue(forKey: #keyPath(Foo.text))
        }
    }
    
    let context: UnsafeMutableRawPointer = .allocate(byteCount: 1, alignment: 1)
    
    override init() {
        super.init()
        addObserver(self, forKeyPath: #keyPath(Foo.text), context: context)
    }
    
    deinit {
        context.deallocate()
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if self.context == context {
            print(object) // 불림!
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
}

let foo: Foo = .init()
foo.text = "TEST"
```

하지만 위에서 보여준 assembly를 보면 KVO 관련 코드가 없는데 이게 어떻게 되는건가 했더니, 그냥 `objc_msgSend`에서 setter로 등록된 `_cmd`가 실행되고 `@sythesize text = text;` 이렇게 되어 있으면 자동으로 KVO 지원이 되는듯? (TODO: 검증 필요)

아래처럼 `dynamic` 키워드 안 쓰고 직접 KVO 코드를 작성한다면 KVO가 되긴 하겠지만, `-setText:`가 불릴 때 이벤트가 두 번 중복으로 날라가는 이슈가 생기므로 추천하진 않음

```swift
@objc(Foo) class Foo: NSObject {
    @objc var text: NSString? {
        willSet {
            willChangeValue(forKey: #keyPath(Foo.text))
        }
        didSet {
            didChangeValue(forKey: #keyPath(Foo.text))
        }
    }
}

let foo: Foo = .init()

// KVO 이벤트 두 번 날라감
foo.perform(#selector(setter: Foo.text), with: "TEST")

// KVO 이벤트 한 번만 날라감
foo.text = "TEST"
```

## Swift class에서

TODO

Swift에서도 dynamic 붙일 수 있음

Swift에서 dynamic 키워드가 없으면 inline하게 getter/setter가 생성되고

dynamic 키워드가 있으면 getter/setter를 호출하는 방식
