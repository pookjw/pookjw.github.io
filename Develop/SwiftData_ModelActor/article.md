# SwiftData에서 ModelActor 사용하기

Core Data의 [`NSManagedObject`](https://developer.apple.com/documentation/coredata/nsmanagedobject)을 비롯해서, SwiftData의 [`PersistentModel`](https://developer.apple.com/documentation/swiftdata/persistentmodel)에서는 thread-safe하지 않습니다.

SwiftData에서는 [`ModelActor`](https://developer.apple.com/documentation/swiftdata/modelactor)를 통해 thread-safe하게 만들 수 있습니다. 이 글에서는 [`ModelActor`]의 사용법을 알게 된 과정, iOS 17.0 beta 1/2의 버그를 임시로 수정하는 방법을 소개합니다.

## 과정

아래처럼 일반적인 Model이 있다고 가정합시다. `@Model`에서는 `@Transient`를 제외한 모든 property들에 `@PersistedProperty` macro를 자동으로 붙여줄 것이며, `@PersistedProperty`는 `backingData`에서 property의 getter/setter를 자동으로 구현해 줍니다.

`backingData`는 일반적으로 [`DefaultBackingData`](https://developer.apple.com/documentation/swiftdata/defaultbackingdata)을 많이 쓸텐데 이게 thread-safe하지 않으므로, 아래 Model은 thread-safe하지 않은 것입니다.

```swift
@Model
final class Note {
    @Attribute([.unique], originalName: nil, hashModifier: nil) let uniqueID: UUID
    @Attribute([.encrypt], originalName: nil, hashModifier: nil) var body: String
    @Attribute var modifiedDate: Date
    @Attribute([.externalStorage], originalName: nil, hashModifier: nil) var imageData: Data?
    
    init(uniqueID: UUID, body: String, modifiedDate: Date, imageData: Data?) {
        self.uniqueID = uniqueID
        self.body = body
        self.modifiedDate = modifiedDate
        self.imageData = imageData
    }
}
```

단순 무식하게 `final class` -> `actor`로 바꾸고, `ModelActor`를 붙여봅시다.

```swift
var defaultModelExecutor: DefaultModelExecutor!

// ModelContext init할 때 defaultModelExecutor 생성하기
// 아래처럼 하면 Actor의 executor를 Context 기반으로 할 수 있음. 만약 thread를 커스텀하고 싶으면 ModelExecutor를 직접 정의하면 됨
// https://github.com/apple/swift-evolution/blob/main/proposals/0392-custom-actor-executors.md
let sdContainer: ModelContainer = try .init(for: [Note.self])
let sdContext: ModelContext = await sdContainer.mainContext
defaultModelExecutor = .init(context: sdContext)

// Model
@Model
actor Note: ModelActor {
    nonisolated var executor: any ModelExecutor { defaultModelExecutor! }
    
    @Attribute([.unique], originalName: nil, hashModifier: nil) let uniqueID: UUID
    @Attribute([.encrypt], originalName: nil, hashModifier: nil) var body: String
    @Attribute var modifiedDate: Date
    
    // TODO: Replace with imageData and migrate it
    @Attribute([.externalStorage], originalName: nil, hashModifier: nil) var imageData: Data?
    
    init(uniqueID: UUID, body: String, modifiedDate: Date, imageData: Data?) {
        self.uniqueID = uniqueID
        self.body = body
        self.modifiedDate = modifiedDate
        self.imageData = imageData
    }
} 
```

위 코드는 컴파일 에러가 납니다. `@Model`과 `@PersistedProperty` macro들은 property의 KeyPath를 활용하는데, macro들은 actor-nonisolated KeyPath를 필요로 합니다. 그 KeyPath들은 actor-isolated이기 때문에 에러가 납니다.

결국 `@Model`과 `@PersistedProperty`을 쓰면 안 되는 것 같네요. 아래처럼 Model을 직접 만들어야 합니다.

```swift
final class NonisolatedValueStore<T: Sendable>: Sendable {
    var value: T?
    
    init(value: T?) {
        self.value = value
    }
}

actor Note: PersistentModel, ModelActor {
    nonisolated var executor: any ModelExecutor {
        defaultModelExecutor!
    }
    
    init(backingData: any BackingData<Note>) {
        self.backingData = backingData
    }
    
    let _backingDataValueStore: NonisolatedValueStore<any BackingData<Note>> = .init(value: DefaultBackingData(for: Note.self))
    nonisolated var backingData: any BackingData<Note> {
        get {
            _backingDataValueStore.value!
        }
        set {
            _backingDataValueStore.value = newValue
        }
    }
    
    static func schemaMetadata() -> [(String, AnyKeyPath, Any?, Any?)] {
        [
            ("number", \Note._uniqueID, nil, Attribute([.unique])),
            ("body", \Note._body, nil, Attribute([.encrypt])),
            ("modifiedDate", \Note._modifiedDate, nil, nil),
            ("imageData", \Note._imageData, nil, Attribute([.externalStorage]))
        ]
    }
    
    private nonisolated var _uniqueID: UUID {
        get {
            backingData.getValue(for: \._uniqueID)
        }
        set {
            backingData.setValue(for: \._uniqueID, to: newValue)
        }
    }
    var uniqueID: UUID {
        get {
            _uniqueID
        }
        set {
            _uniqueID = newValue
        }
    }
    
    private nonisolated var _body: String {
        get {
            backingData.getValue(for: \._body)
        }
        set {
            backingData.setValue(for: \._body, to: newValue)
        }
    }
    var body: String {
        get {
            _body
        }
        set {
            _body = newValue
        }
    }

    private nonisolated var _modifiedDate: Date {
        get {
            backingData.getValue(for: \._modifiedDate)
        }
        set {
            backingData.setValue(for: \._modifiedDate, to: newValue)
        }
    }
    var modifiedDate: Date {
        get {
            _modifiedDate
        }
        set {
            _modifiedDate = newValue
        }
    }
    
    private nonisolated var _imageData: Data? {
        get {
            backingData.getValue(for: \._imageData)
        }
        set {
            backingData.setValue(for: \._imageData, to: newValue)
        }
    }
    var imageData: Data? {
        get {
            _imageData
        }
        set {
            _imageData = newValue
        }
    }
    
    init(uniqueID: UUID, body: String, modifiedDate: Date, imageData: Data?) {
        self._uniqueID = uniqueID
        self._body = body
        self._modifiedDate = modifiedDate
        self._imageData = imageData
    }
}
```

## iOS 17.0 beta 1/2에서 문제점

위 코드를 iOS 17.0 beta 1/2 환경에서 돌리면 아래처럼 크래시가 납니다.

```
objc[38405]: objc_setAssociatedObject called on instance (0x6000002a6ea0) of class Noteground.Note which does not allow associated objects
(lldb) bt
* thread #1, queue = 'com.apple.main-thread', stop reason = signal SIGABRT
    frame #0: 0x000000010460cdb0 libsystem_kernel.dylib`__abort_with_payload + 8
    frame #1: 0x0000000104630ec0 libsystem_kernel.dylib`abort_with_payload_wrapper_internal + 100
    frame #2: 0x0000000104630e5c libsystem_kernel.dylib`abort_with_reason + 28
    frame #3: 0x000000018005beb4 libobjc.A.dylib`_objc_fatalv(unsigned long long, unsigned long long, char const*, char*) + 112
    frame #4: 0x000000018005be44 libobjc.A.dylib`_objc_fatal(char const*, ...) + 28
    frame #5: 0x0000000180052450 libobjc.A.dylib`objc_setAssociatedObject + 1136
    frame #6: 0x00000001a945e64c SwiftData`SwiftData.PersistentModel._metadata() -> SwiftData._ModelMetadata + 312
```

`objc_setAssociatedObject`의 `x0` register에 actor 타입이 쌩으로 들어가서 생기는 문제입니다.

- 왜인지는 모르겠으나 actor가 Objective-C Runtime으로 넘어갈 떄 `__SwiftValue`로 변환되지 않는 것 같네요. Swift 버그로 보이는데... class는 `__SwiftValue`로 잘 변환되는데 말이죠.
- 애초에 Swift Type을 `id` parameter에 넣는 것은 위험하다고 생각하는데;; SwiftData 내부 구조도 왜 저렇게 짰을지....

이상한 점들이 여러가지네요. 한 번 actor를 NSObject 기반으로 바꿔봅시다.

```swift
actor Note: NSObject, PersistentModel, ModelActor
```

그러면 Runtime에서 아래와 같은 에러가 납니다.

```
SwiftData/Schema.swift:294: Fatal error: Entity Note specifies SwiftNativeNSObject as its parent but no such entity was found in the provided types: [Noteground.Note]
```

뭔 소리인가 했더니 actor가 NSObject를 subclassing하면, NSObject를 subclassing하지 않고 SwiftNativeNSObject를 subclassing하고 있네요.

```
(lldb) expression -l objc -O -- [NSClassFromString(@"_TtC10Noteground4Note") superclass]
SwiftNativeNSObject
```

SwiftData는 SwiftNativeNSObject이 뭔지 모르니까 Model type으로 인식해 버린거고, 아까 위 코드 `let sdContainer: ModelContainer = try .init(for: [Note.self])`에서 type들에 SwiftNativeNSObject을 정의하지 않았기 때문에 크래시가 발생하네요.... 총체적 난국 ㅎㅎㅎ;;

일단 NSObject를 subclassing하는 것은 포기하고 다른 방법을 모색해 봅시다. NSObject 표기를 지우고, `objc_setAssociatedObject`와 `objc_getAssociatedObject`들이 호출될 때마다 `x0` register에 아래처럼 임의의 NSObject 메모리 주소를 주입해주면 해결될 것 같네요.

참고로 아래에서 설명하는 offset은 SDK마다 다를 수 있기에... assembly 읽어보고 offset을 정확히 구하시는걸 추천

```
# SwiftData._ModelMetadata의 메모리 주소 가져옴
(lldb) image lookup -vn '$s9SwiftData15PersistentModelPAAE9_metadataAA01_D8MetadataCyF'
1 match found in /Library/Developer/CoreSimulator/Volumes/iOS_21A5268h/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 17.0.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/SwiftData.framework/SwiftData:
        Address: SwiftData[0x000000000004e514] (SwiftData.__TEXT.__text + 314832)
        Summary: SwiftData`SwiftData.PersistentModel._metadata() -> SwiftData._ModelMetadata
         Module: file = "/Library/Developer/CoreSimulator/Volumes/iOS_21A5268h/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 17.0.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/SwiftData.framework/SwiftData", arch = "arm64"
         Symbol: id = {0x000031d8}, range = [0x00000001a945e514-0x00000001a945e674), name="SwiftData.PersistentModel._metadata() -> SwiftData._ModelMetadata", mangled="$s9SwiftData15PersistentModelPAAE9_metadataAA01_D8MetadataCyF"
         
# objc_getAssociatedObject 호출하는 곳 메모리 주소 구함 (offset: +56)
(lldb) p/x 0x00000001a945e514 + 56
(Int) 0x00000001a945e54c

# objc_setAssociatedObject 호출하는 곳 메모리 주소 구함 (offset: +308)
(lldb) p/x 0x00000001a945e514 + 308
(Int) 0x00000001a945e648

# 임의의 NSObject 생성
(lldb) p/x [NSObject new]
(NSObject *) 0x000060000003c0d0

# breakpoint 설정
(lldb) breakpoint set -a 0x00000001a945e648 -G1 -C 'register write x0 0x000060000003c0d0'
Breakpoint 2: where = SwiftData`SwiftData.PersistentModel._metadata() -> SwiftData._ModelMetadata + 308, address = 0x00000001a945e648
(lldb) breakpoint set -a 0x00000001a945e54c -G1 -C 'register write x0 0x000060000003c0d0'
Breakpoint 3: where = SwiftData`SwiftData.PersistentModel._metadata() -> SwiftData._ModelMetadata + 56, address = 0x00000001a945e54c
```

이렇게 `x0` register 값을 변조하면 잘 작동하네요.

Model type이 여러개면 크래시날 가능성 있는데... 그건 알아서 해결하시길 ㅎ
