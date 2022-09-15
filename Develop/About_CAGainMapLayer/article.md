# Dynamic Island에서 쓰이는 도형 랜더링을 써보자

![](0.png)

[출처](https://meeco.kr/mini/36020240)

iPhone 14 Pro / Pro Max에 탑재된 Dyanmic Island에는 위 사진처럼 독특한 형태의 Corner Radius가 적용되어 있습니다.

제가 이전에 [iPhone 14 Pro (Max)에서 Dynamic Island 영역을 투명하게 만들기](/Develop/Aperture_with_Clear_Color/article.md)이라는 글을 작성했습니다. 보시면 Dynamic Island를 표현하는 View는 `_SBGainMapView`이며 `CAGainMapLayer`라는 커스텀 `CALayer`를 가지고 있습니다.

문득... 이걸 직접 써볼까? 해서 직접 써봤습니다.

![](1.png)

중앙에 위치한 첫번째 원은 저희가 일반적으로 구현이 가능한 View이며, 두번째는 `CAGainMapLayer`를 사용한 View 입니다. 확대해보면

![](2.png)

직선과 곡선의 표현에서 차이가 확실하게 보이는데요.

- 직선 : 첫번째는 단순 직선인 것에 비해, 두번째는 회색 선이 있음.

- 곡선 : 첫번째는 곡선의 색 패턴이 일정한데, 두번째는 색 패턴이 밝아졌다 어두워졌다를 반복함.

이런 차이가 보이네요. 해당 부분의 소스 코드는 아래와 같습니다.

iOS 16.0 베타 및 iPadOS 16.1 베타 1에서는 해당 API가 존재하지 않아서 크래시가 납니다. 또한 iPhone 14 Pro / Pro Max 및 Simulator에서만 정상적으로 랜더링되며, 그 외 환경에서는 폰 화면이 검정색으로 변합니다. 아마 디스플레이 전용 칩셋이 없어서 그런 것 같네요...

```objc
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>

@interface GainMapView : UIView
@end

@implementation GainMapView

+ (Class)layerClass {
  return NSClassFromString(@"CAGainMapLayer");
}

- (instancetype)initWithFrame:(CGRect)frame {
  if (self = [super initWithFrame:frame]) {
    ((void (*)(id, SEL, NSString *))objc_msgSend)(self.layer, NSSelectorFromString(@"setRenderMode:"), @"gainFill");
  }

  return self;
}

@end

@interface ViewController : UIViewController
@end

@interface ViewController ()
@property (strong) UIStackView *stackView;
@property (strong) UIView *normalView;
@property (strong) GainMapView *gainMapView;
@property void *normalViewObservationContext;
@property void *circleViewObservationContext;
@end

@implementation ViewController

- (void)dealloc {
  [self.normalView removeObserver:self forKeyPath:@"bounds" context:self.normalViewObservationContext];
  [self.gainMapView removeObserver:self forKeyPath:@"bounds" context:self.circleViewObservationContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
  if ((context == self.circleViewObservationContext) || (context == self.normalViewObservationContext)) {
    [NSOperationQueue.mainQueue addOperationWithBlock:^{
      __kindof UIView *targetView = (__kindof UIView *)object;
      targetView.layer.cornerRadius = targetView.frame.size.height / 2.0f;
    }];
  } else {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
  }
}

- (void)viewDidLoad {
  [super viewDidLoad];

  self.view.backgroundColor = UIColor.whiteColor;

  UIStackView *stackView = [UIStackView new];
  stackView.backgroundColor = UIColor.clearColor;
  stackView.axis = UILayoutConstraintAxisVertical;
  stackView.distribution = UIStackViewDistributionFillEqually;
  stackView.spacing = 20.0f;
  stackView.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:stackView];
  [NSLayoutConstraint activateConstraints:@[
    [stackView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [stackView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    [stackView.widthAnchor constraintEqualToConstant:200.0f],
    [stackView.heightAnchor constraintEqualToConstant:220.0f]
  ]];

  UIView *normalView = [UIView new];
  normalView.backgroundColor = UIColor.blackColor;
  [stackView addArrangedSubview:normalView];
  [normalView addObserver:self forKeyPath:@"bounds" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:self.normalViewObservationContext];

  GainMapView *gainMapView = [GainMapView new];
  gainMapView.backgroundColor = UIColor.blackColor;
  [stackView addArrangedSubview:gainMapView];
  [gainMapView addObserver:self forKeyPath:@"bounds" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:self.circleViewObservationContext];

  self.stackView = stackView;
  self.normalView = normalView;
  self.gainMapView = gainMapView;
}

@end
```
