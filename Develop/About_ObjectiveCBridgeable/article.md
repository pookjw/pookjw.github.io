# ObjectiveCBridgeable

Swift 소스코드를 보다가 [BridgeObjectiveC.swift](https://github.com/apple/swift/blob/main/stdlib/public/core/BridgeObjectiveC.swift)라는 것을 발견해서 글을 남깁니다.

Swift에는 [String](https://developer.apple.com/documentation/swift/string), [Date](https://developer.apple.com/documentation/foundation/date), [Data](https://developer.apple.com/documentation/foundation/data) 등의 타입이 존재합니다. 이는 아래처럼 Objective-C 타입으로 변환시킬 수 있는데요.

```swift
let string: String = /* */
let nsString: NSString = string as NSString

let date: Date = /* */
let nsDate: NSDate = date as NSDate

let data: Data = /* */
let nsData: NSData = data as NSData
```

이는 [NSDiffableDataSourceSnapshot](https://developer.apple.com/documentation/uikit/nsdiffabledatasourcesnapshot)도 비공식적으로 지원합니다. Swift 타입은 `__SwiftValue`라 불리는 NSObject 형태로 변환되는 것도 볼 수 있습니다.

```swift
enum Section: Int, Identifiable {
    case fruit
    var id: Int { rawValue }
}

enum Item: Int, Identifiable {
    case apple, banana, kiwi
    var id: Int { rawValue }
}

var snapshot: NSDiffableDataSourceSnapshot<Section, Item> = .init()
snapshot.appendSections([.fruit])
snapshot.appendItems([.apple, .banana, .kiwi], toSection: .fruit)

let bridged: NSDiffableDataSourceSnapshotReference = snapshot as NSDiffableDataSourceSnapshotReference
bridged.itemIdentifiers.forEach {
    print(type(of: $0)) // __SwiftValue
    print(($0 as! NSObject).isKind(of: NSObject.self)) // true
}
```

이렇게 `as`라는 키워드 하나로 Swift 타입과 Objective-C 타입을 쉽게 오갈 수 있습니다. 이는 `_ObjectiveCBridgeable`라는 protocol 덕분에 가능합니다.

예시로 `SwiftView`라는 Swift 타입을 만들어 보겠습니다. [`UIView`](https://developer.apple.com/documentation/uikit/uiview)에서 [backgroundColor](https://developer.apple.com/documentation/uikit/uiview/1622591-backgroundcolor)를 유지한채 Swift 타입과 Objective-C 타입이 bridging 되는 구조입니다.

```swift
struct SwiftView: _ObjectiveCBridgeable {
    typealias _ObjectiveCType = UIView
    
    var backgroundColor: UIColor? = nil
    
    func _bridgeToObjectiveC() -> UIView {
        let uiView: UIView = .init()
        uiView.backgroundColor = backgroundColor
        return uiView
    }
    
    static func _forceBridgeFromObjectiveC(_ source: UIView, result: inout SwiftView?) {
        var new: SwiftView = .init()
        new.backgroundColor = source.backgroundColor
        result = new
    }
    
    static func _conditionallyBridgeFromObjectiveC(_ source: UIView, result: inout SwiftView?) -> Bool {
        _forceBridgeFromObjectiveC(source, result: &result)
        return true
    }
    
    static func _unconditionallyBridgeFromObjectiveC(_ source: UIView?) -> SwiftView {
        var new: SwiftView = .init()
        new.backgroundColor = source?.backgroundColor
        return new
    }
}
```

그러면 아래처럼 briding이 쉽게 가능해 집니다.

```swift
class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        var swiftView: SwiftView = .init()
        swiftView.backgroundColor = .orange
        
        let uiView: UIView = swiftView as UIView
        view.addSubview(uiView)
        uiView.frame = view.bounds
    }
}
```

문득... SwiftUI의 [Color](https://developer.apple.com/documentation/swiftui/color)와 UIKit의 [UIColor](https://developer.apple.com/documentation/uikit/uicolor)의 brigding 구조도 만들 수 있지 않을까? 싶어서 한 번 해봤습니다.

```swift
extension Color: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = UIColor

    public func _bridgeToObjectiveC() -> UIColor {
        let uiColor: UIColor = .init(cgColor: cgColor!)
        return uiColor
    }

    public static func _forceBridgeFromObjectiveC(_ source: UIColor, result: inout Color?) {
        result = .init(uiColor: source)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: UIColor, result: inout Color?) -> Bool {
        _forceBridgeFromObjectiveC(source, result: &result)
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: UIColor?) -> Color {
        return .init(uiColor: source!)
    }
}
```

그러면 아래처럼 쓸 수 있게 될거라 예상했습니다.

```swift
let color: Color = .orange
let uiColor: UIColor = color as UIColor
```

하지만 아쉽게도 빌드 에러가 납니다. 뭔가 막혀 있는 듯 하네요.

    Conformance of 'Color' to '_ObjectiveCBridgeable' can only be written in module 'SwiftUI'
