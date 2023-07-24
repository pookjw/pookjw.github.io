# Swift Concurrency와 Objective-C 혼용 팁

Swift Concurrency와 Objective-C를 혼용할 때 팁을 적는 글이에요.

기본 지식은 [Concurrency Interoperability with Objective-C](https://github.com/apple/swift-evolution/blob/main/proposals/0297-concurrency-objc.md)를 참고하시면 좋을 것 같아요. 이 글에 대해서는 다루지 않아요.

## Task - Internal 함수들

Swift Conrrency의 Task에서는 Internal 함수를 제공하고 있어요.

https://github.com/apple/swift/blob/01086bc8b5d327ae44e94279a2f4ae4503af859c/stdlib/public/Concurrency/Task.swift#L922

Public은 아니지만 `@_silgen_name`으로 정의되어 있기 때문에 [`dlsym`](https://man7.org/linux/man-pages/man3/dlsym.3.html)으로 손쉽게 호출할 수 있어요.

여기서 쓸만한 예제를 정리할게요. 생각날 때마다 꾸준히 업데이트 예정

### `isCancelled`

Swift에서는 Task가 취소되었는지를 확인하는 [`Task.isCancelled`](https://developer.apple.com/documentation/swift/task/iscancelled-swift.type.property) API가 존재하지만 애플이 C에서는 API를 제공하고 있지 않습니다.

이를 C에서 구현하기 위해서 isCancelled가 무슨 원리인지를 보면

https://github.com/apple/swift/blob/a04d273f9b4cc70891dd957df92bc521c6ecc307/stdlib/public/Concurrency/TaskCancellation.swift#L80

- [`withUnsafeCurrentTask(body:)`](https://developer.apple.com/documentation/swift/withunsafecurrenttask(body:))로 UnsafeCurrentTask를 가져 옴

- UnsafeCurrentTask의 isCancelled 호출

이런 원리이기에 Internal 함수에서는

- `swift_task_getCurrent`를 호출해서 현재 Task를 가져 옴

- `swift_task_isCancelled`를 호출해서 취소 여부 확인

이렇게 하면 될 것 같네요.

테스트를 위해 아래처럼 AsyncObject를 정의하고

```objc
#pragma mark - AsyncObject.h

#import <Foundation/Foundation.h>

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

@interface AsyncObject : NSObject
- (void)performWithCompletionHandler:(void (^)(void))completionHandler;
@end

NS_HEADER_AUDIT_END(nullability, sendability)
```

```objc
#pragma mark - AsyncObject.mm

#import "AsyncObject.h"
#import <dlfcn.h>

@implementation AsyncObject

- (void)performWithCompletionHandler:(void (^)(void))completionHandler {
    void *handle = dlopen("/usr/lib/swift/libswift_Concurrency.dylib", RTLD_NOW);
    auto _getCurrentAsyncTask = reinterpret_cast<void *(*)(void)>(dlsym(handle, "swift_task_getCurrent"));
    void *currentTask = _getCurrentAsyncTask();
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        auto _taskIsCancelled = reinterpret_cast<bool (*)(void *)>(dlsym(handle, "swift_task_isCancelled"));
        bool isCancelled = _taskIsCancelled(currentTask);
        
        if (isCancelled) {
            NSLog(@"Cancelled!");
        }
        
        completionHandler();
    });
}

@end
```

Swift 코드에서는 아래처럼 실행하면

```swift
let task: Task<Void, Never> = .init {
    try? await Task.sleep(for: .seconds(1))
    let object: AsyncObject = .init()
    await object.perform()
}

task.cancel()
```

`Cancelled`라는 로그가 잘 찍히는 것을 확인할 수 있네요.

이렇게 하면 C에서도 취소 핸들링이 가능하네요.

TODO: Swift ABI의 이해도가 높아지면 Swift API 직접 호출해보는 방법도 있을듯? https://github.com/apple/swift/blob/a04d273f9b4cc70891dd957df92bc521c6ecc307/utils/api_checker/FrameworkABIBaseline/_Concurrency/ABI/macos.json

## Macro

- `NS_SWIFT_DISABLE_ASYNC`

- `UIKIT_SWIFT_ACTOR_INDEPENDENT`

- `NS_SWIFT_UI_ACTOR`

- `NS_HEADER_AUDIT_BEGIN(nullability, sendability)`

- `NS_HEADER_AUDIT_END(nullability, sendability)`
