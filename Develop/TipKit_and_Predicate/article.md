# TipKit, 그리고 Swift 5.9의 Predicate

![](0.png)

iOS 17.0 beta 4 SDK 부터 TipKit이 공개되었다.

- SwiftUI 기반

- TipsNextCore라는 Private Framework를 기반으로 동작

- Objective-C API도 제공하나 사실상 없는 수준

- UIKit/AppKit 호환성이 있음

- Tip을 시간 주기로 띄우거나 특정 조건에 따라 뜨게 하는 것이 가능

- 데이터 기록 용도로 내부적으로 SwiftData를 사용

대충 이정도로 요약할 수 있다.

아마 옛날에는 Objective-C로 구현된 Private Framework가 있었을텐데 (이름 까먹음) 이번에 SwiftUI로 재작성해서 Public으로 공개했다.

## BPTipKit: TipKit for Objective-C 

아직 작업 중이긴 한데... TipKit을 Objective-C에서 쓸 수 있게 API Wrapper를 만들어봤다.

https://github.com/pookjw/BPTipKit

사용법은 대충 아래와 같다.

우선 configure를 해줘야 한다. 위에서 설명했다시피 TipKit은 내부적으로 SwiftData를 쓰며 [DatastoreLocation](https://developer.apple.com/documentation/tipkit/datastorelocation)를 통해 Container URL를 변경할 수 있다. 마찬가지로 BPTipKit에서는 `BPDatastoreLocation`를 사용하면 된다.

```objc
NSArray<id<BPTipsConfiguration>> *configurations = @[
    BPDatastoreLocation.applicationDefaultDatastoreLocation,
    BPDisplayFrequency.immediateFrequency
];

[BPTips configureWithConfigurations:configurations completionHandler:^(NSError * _Nullable error) {

}];
```

그 다음에 아래처럼 Tip의 정보를 정의한다.

```objc
@interface Tip : NSObject <BPTip>
@end

@implementation Tip

- (NSAttributedString *)title {
    return [[NSAttributedString alloc] initWithString:@"Hello World!" attributes:@{NSForegroundColorAttributeName: UIColor.systemRedColor}];
}

@end
```

그러면 아래 코드로 `BPTipUIView`를 통해 Tip View를 만들 수 있다.

```objc
Tip *tip = [Tip new];

BPTipUIView *tipView = [[BPTipUIView alloc] initWithBPTip:tip arrowEdge:NSDirectionalRectEdgeLeading actionHandler:^(BPTipsAction * _Nonnull action) {

}];
```

[`statusUpdates`](https://developer.apple.com/documentation/tipkit/tip/statusupdates) 및 [`shouldDisplayUpdates`](https://developer.apple.com/documentation/tipkit/tip/shoulddisplayupdates)도 지원한다. 이를 구현하기 위해 Swift의 `AsyncStream`을 `BPTipCancellable`라는 객체로 변환시켜봤다. [`NSKeyValueObservation`](https://github.com/apple/swift-corelibs-foundation/blob/9cf3489411e35a737c2d2de63f50677d5ce8a4a8/Darwin/Foundation-swiftoverlay/NSObject.swift#L163)에서 영감을 얻었다. `BPTipCancellable`가 release되면 `AsyncStream`이 cancel 되는 구조다.

```objc
Tip *tip = [Tip new];
BPTipStatus *status = [[BPTipStatus alloc] initWithBPTip:tip];

BPTipCancellable *statusUpdatesOberver = [status observeStatusUpdatesWithHandler:^{

}];

BPTipCancellable *shouldDisplayUpdatesObserver = [status observeShouldDisplayUpdatesWithHandler:^(BOOL newValue) {

}];
```

대충 이런 식으로 웬만한 기능을 지원한다. **[`Tips.Rule`](https://developer.apple.com/documentation/tipkit/tips/rule) 빼고**

## Tips.Rule, 그리고 BPTipsParameterRule

TipKit에는 Rule이라는 기능이 있다. 시간 및 특정 조건에 따라 Tip이 뜰지 말지를 정한다. 이 조건은 [`StandardPredicateExpression`](https://developer.apple.com/documentation/foundation/standardpredicateexpression)과 `#Rule`이라는 macro도 정의한다.

나는 NSPredicate가 유사하다고 생각했기에, [`Tips.Parameter`](https://developer.apple.com/documentation/tipkit/tips/parameter)를 BPTipKit에 적용하기 위해 아래와 같은 API를 구상했다.

```objc
@interface Tip : NSObject <BPTip>
@end

@implementation Tip

- (NSAttributedString *)title {
    return [[NSAttributedString alloc] initWithString:@"Hello World!" attributes:@{NSForegroundColorAttributeName: UIColor.systemRedColor}];
}

- (NSArray<id<BPTipsRule>> *)rules {
    BPTipsParameterValue *defaultValue = [[BPTipsParameterValue alloc] initWithValue:@YES];
    BPTipsParameter *parameter = [[BPTipsParameter alloc] initWithDefaultValue:defaultValue key:@"key" isTransient:NO];
    
    NSPredicate *predicate = [NSPredicate predicateWithValue:YES];
    BPTipsParameterRule *rule = [[BPTipsParameterRule alloc] initWithParameter:parameter predicate:predicate];
    
    return @[rule];
}

@end
```

위 predicate의 evaluation 결과는 항상 `YES`이므로 tip이 뜨게 된다. BPTipKit의 해당 로직도 살짝 보여주면

우선 아래 코드는 `NSPredicate`를 `StandardPredicateExpression`로 변환하는 `NSPredicateExpression`를 정의한다.

```swift
extension PredicateExpressions {
    struct NSPredicateExpression<Value: PredicateExpression>: PredicateExpression {
        let value: Value
        let nsPredicate: NSPredicate
        
        func evaluate(_ bindings: PredicateBindings) throws -> Bool {
            let value = try value.evaluate(bindings)
            
            return nsPredicate.evaluate(with: value)
        }
    }
}

extension PredicateExpressions.NSPredicateExpression : StandardPredicateExpression where Value : StandardPredicateExpression {}

extension PredicateExpressions.NSPredicateExpression : Codable where Value : Codable {
    enum CodingKeys: String, CodingKey {
        case value
        case nsPredicate
    }
    
    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        let nsPredicateData: Data = try container.decode(Data.self, forKey: .nsPredicate)
        guard let nsPredicate: NSPredicate = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSPredicate.self, from: nsPredicateData) else {
            fatalError()
        }
        
        value = try container.decode(Value.self, forKey: .value)
        self.nsPredicate = nsPredicate
    }
    
    func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        let nsPredidateData: Data = try NSKeyedArchiver.archivedData(withRootObject: nsPredicate, requiringSecureCoding: true)
        
        try container.encode(value, forKey: .value)
        try container.encode(nsPredidateData, forKey: .nsPredicate)
    }
}
```

만약 Swift의 Predicate의 내부 동작 원리에 대해 잘 아는 사람이라면 위 코드는 말이 안 된다고 생각할 것이다. 이는 후술한다.

이제 위 `NSPredicateExpression`를 통해 `NSPredidate`를 [`Tip.Rule`](https://developer.apple.com/documentation/tipkit/tips/rule/init(_:_:)-7zy3y)로 변환한다.

```swift
extension BPTips {
    @objc(BPTipsParameterRule)
    open class ParameterRule: NSObject, @unchecked Sendable, BPTipsRule, BPTipsRulePresentable {
        @objc public let parameter: Parameter
        public let rule: Tips.Rule
        
        @objc(initWithParameter:predicate:)
        public init(parameter: Parameter, predicate: NSPredicate) {
            self.parameter = parameter
            rule = .init(parameter.parameter) { value in
                PredicateExpressions.NSPredicateExpression(value: value, nsPredicate: predicate)
            }
        }
    }
}
```

Compile에는 문제 없다. 하지만 Runtime에서 `EXC_BREAKPOINT`가 발생한다.

```
(lldb) bt
* thread #2, queue = 'com.apple.root.user-initiated-qos.cooperative', stop reason = EXC_BREAKPOINT (code=1, subcode=0x10215690c)
  * frame #0: 0x000000010215690c TipKit`___lldb_unnamed_symbol1568 + 368
    frame #1: 0x00000001021563bc TipKit`___lldb_unnamed_symbol1565 + 160
    frame #2: 0x0000000102152188 TipKit`TipKit.Tips.Rule.init<τ_0_0, τ_0_1 where τ_0_0: Swift.Decodable, τ_0_0: Swift.Encodable, τ_0_0: Swift.Sendable, τ_0_1: Foundation.StandardPredicateExpression, τ_0_1.Output == Swift.Bool>(TipKit.Tips.Parameter<τ_0_0>, (Foundation.PredicateExpressions.Variable<τ_0_0>) -> τ_0_1) -> TipKit.Tips.Rule + 240
    frame #3: 0x000000010099ae04 BPTipKitDemo_iOS`BPTips.ParameterRule.init(parameter=0x0000600000008620, predicate=0x00000001c21781a0) at BPTipsParameterRule.swift:109:21
    frame #4: 0x000000010099af70 BPTipKitDemo_iOS`@objc BPTips.ParameterRule.init(parameter:predicate:) at <compiler-generated>:0
    frame #5: 0x000000010098b254 BPTipKitDemo_iOS`-[Tip rules](self=0x00006000000048a0, _cmd="rules") at ViewController.m:37:33
```

...

찾아보니 `Predicate`는 오픈소스다. 한 번 [`PredicateExpressions.Equal`](https://developer.apple.com/documentation/foundation/predicateexpressions/equal)의 [소스코드](https://github.com/apple/swift-foundation/blob/main/Sources/FoundationEssentials/Predicate/Expressions/Equality.swift)를 복붙해보고 이름만 바꿔보자

```swift
extension PredicateExpressions {
    public struct MyEqual<
        LHS : PredicateExpression,
        RHS : PredicateExpression
    > : PredicateExpression
    where
        LHS.Output == RHS.Output,
        LHS.Output : Equatable
    {
        public typealias Output = Bool
        
        public let lhs: LHS
        public let rhs: RHS
        
        public init(lhs: LHS, rhs: RHS) {
            self.lhs = lhs
            self.rhs = rhs
        }
        
        public func evaluate(_ bindings: PredicateBindings) throws -> Bool {
            try lhs.evaluate(bindings) == rhs.evaluate(bindings)
        }
    }
    
    public static func build_Equal<LHS, RHS>(lhs: LHS, rhs: RHS) -> MyEqual<LHS, RHS> {
        MyEqual(lhs: lhs, rhs: rhs)
    }
}

extension PredicateExpressions.MyEqual : StandardPredicateExpression where LHS : StandardPredicateExpression, RHS : StandardPredicateExpression {}

extension PredicateExpressions.MyEqual : Codable where LHS : Codable, RHS : Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(lhs)
        try container.encode(rhs)
    }
    
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        lhs = try container.decode(LHS.self)
        rhs = try container.decode(RHS.self)
    }
}

extension PredicateExpressions.MyEqual : Sendable where LHS : Sendable, RHS : Sendable {}
```

그 다음에 `Tips.Rule` 생성하는 부분을 아래 코드처럼 하자. true와 true의 값 비교이기에 무조건 true가 나올 것이다.

```swift
extension BPTips {
    @objc(BPTipsParameterRule)
    open class ParameterRule: NSObject, @unchecked Sendable, BPTipsRule, BPTipsRulePresentable {
        @objc public let parameter: Parameter
        public let rule: Tips.Rule
        
        @objc(initWithParameter:predicate:)
        public init(parameter: Parameter, predicate: NSPredicate) {
            self.parameter = parameter
            rule = .init(parameter.parameter) { value in
                PredicateExpressions.MyEqual(lhs: PredicateExpressions.Value(true), rhs: PredicateExpressions.Value(true))
            }
        }
    }
}
```

하지만 여전히 `EXC_BREAKPOINT`가 나온다.

이 에러의 원인은 Predicate의 내부 동작 구조를 알아야 이해할 수 있다.

## Swift 5.9 - Predicate

Swift 5.9에 추가된 Predicate 기능은 정말 강력하다. Swift 코드로 format 기반 NSPredicate를 생성할 수 있다. 또한 compile-time에서 유효성 검증까지 해주니 기존 NSPredicate의 format에 고통받던 사람이라면 감탄만 나온다 ㅎ

이는 Swift 5.9에서 추가된 Macro 기능과 [Value and Type Parameter Packs](https://github.com/apple/swift-evolution/blob/main/proposals/0393-parameter-packs.md)와 궁합이 정말 좋다.

```swift
let messagePredicate = #Predicate<Message> { message in
    message.length < 100 && message.sender == "Jeremy"
}
```

위 코드의 경우, `Value and Type Parameter Packs` 기능으로 block이 [`PredicateExpressions.Comparison`](https://developer.apple.com/documentation/foundation/predicateexpressions/comparison), [`PredicateExpressions.Equal`](https://developer.apple.com/documentation/foundation/predicateexpressions/equal)로 compile-time에서 변환된다. (`&&`은 뭘로 되징...?)

이렇게 만들어진 Predicate는 `NSPredicate`로 변환할 수 있다! [Apple Documentation](https://developer.apple.com/documentation/foundation/predicateexpressions/equal), [소스코드](https://github.com/apple/swift-foundation/blob/0eeb99ba7bcd36a6e4b3e7daa14ad76d77a42640/Sources/FoundationEssentials/Predicate/NSPredicateConversion.swift#L524)

이러한 모든 Expression들은 [`ConvertibleExpression`](https://github.com/apple/swift-foundation/blob/main/Sources/FoundationEssentials/Predicate/NSPredicateConversion.swift#L524)을 따르면서 Runtime에서 내부적으로 `NSPredicate` 및 `NSExpression` 등으로 변환한다. 예를 들어 `PredicateExpressions.Equal`의 경우 [링크](https://github.com/apple/swift-foundation/blob/0eeb99ba7bcd36a6e4b3e7daa14ad76d77a42640/Sources/FoundationEssentials/Predicate/NSPredicateConversion.swift#L205)

```swift
extension PredicateExpressions.Equal : ConvertibleExpression {
    fileprivate func convert(state: inout NSPredicateConversionState) throws -> ExpressionOrPredicate {
        .predicate(NSComparisonPredicate(leftExpression: try lhs.convertToExpression(state: &state), rightExpression: try rhs.convertToExpression(state: &state), modifier: .direct, type: .equalTo))
    }
}
```

요런 식으로 한다.

문제는 `ConvertibleExpression`은 Private API다. 이 말은 **개발자는 Expression을 직접 만들면 안 되며 애플이 기본적으로 제공하는 것만 써야 한다.**

위에서 내가 Expression을 직접 만들 경우 `ConvertibleExpression`이라는 protocol을 따르지 않기에, `NSPredicate` 변환 과정에서 `nil`이 반환되어 `EXC_BREAKPOINT`이 발생하는 것이다. 아까 크래시가 났던 `0x000000010215690c`을 보면 retain을 실패해서 그런 것이다.

이건 향후 Swift Foundation에서 개선해야 하는 부분으로 보인다.

## 마무리

암튼 BPTipKit을 만들다가 Swift Foundation의 한계로 인해 Rule 기능을 구현하지 못하게 되었다.

그래도 TipKit의 API 하나하나를 다 써보게 되는 계기가 되었고 Predicate의 구조도 알게 된 기회였다 ㅎ
