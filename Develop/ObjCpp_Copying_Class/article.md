# [Objective-C++] 포인터 주소를 가진 객체의 복사

C++에서 객체 복사를 공부하면서 남기는 글입니다.

## C++ 객체

아래와 같은 `CppClass`라는 C++ 객체를 정의합니다.

```cpp
class CppClass {
    NSInteger *number;
public:
#pragma mark - Constructors
    CppClass();
    CppClass(const NSInteger number);
    
#pragma mark - Desctructors
    ~CppClass();
};
```

```cpp
CppClass::CppClass() {
    this->number = new NSInteger;
}

CppClass::CppClass(const NSInteger number) {
    this->number = new NSInteger;
    memcpy(this->number, &number, sizeof(number));
}

CppClass::~CppClass() {
    delete this->number;
}
```

이제 `CppClass`를 생성하고 복사하는 코드를 실행합니다.

```cpp
int main(int argc, const char * argv[]) {
    CppClass original {3};
    CppClass copy = original; // 복사
    return 0;
}
```

그러면 `copy`의 destructor에서 Runtime Error가 발생합니다.

```
malloc: *** error for object 0x60000000c020: pointer being freed was not allocated
malloc: *** set a breakpoint in malloc_error_break to debug
```

이러한 Error가 발생하는 이유는 `copy = original`에서 복사를 시도했기 때문입니다. 복사를 시도하면 `number`라는 포인터 주소가 같이 복사가 되며, original과 copy가 Stack이 소멸됨에 따라 destructor가 각각 불리게 됩니다. 즉, 동일한 메모리 주소의 `number` 포인터에 `delete this->number;`가 두 번 불리므로 Error가 발생합니다.

이를 해결하기 위해 copy가 발생될 때 포인터 주소를 복사하지 말고, 메모리를 새로 할당한 다음 값을 복사해야 합니다. 아래처럼 Copy Constructor를 정의해 줍시다.

```cpp
class CppClass {
    NSInteger *number;
public:
#pragma mark - Constructors
    CppClass();
    CppClass(const NSInteger number);
    
#pragma mark - Desctructors
    ~CppClass();
   
#pragma mark - Copy Constructors
    CppClass(const CppClass &other);
    CppClass & operator=(const CppClass &other);
};
```

```cpp
CppClass::CppClass(const CppClass &other) {
    this->number = new NSInteger;
    memcpy(this->number, other.number, sizeof(number));
}

CppClass & CppClass::operator=(const CppClass &other) {
    delete this->number;
    this->number = new NSInteger;
    memcpy(this->number, other.number, sizeof(number));

    return *this;
}
```

그러면 문제 없이 잘 작동되는 것을 보실 수 있습니다.

## Objectice-C++ 객체

Objective-C++에서도 NSCopying을 통해 객체 복사를 할 수 있습니다. 아래와 같이 `ObjCppClass`라는 NSObject 객체를 정의합니다.

```objc
@interface ObjCppClass : NSObject <NSCopying>
- (instancetype)initWithNumber:(NSInteger)number;
@end
```

```objc
@interface ObjCppClass ()
@property NSInteger *number;
@end

@implementation ObjCppClass

- (instancetype)init {
    if (self = [super init]) {
        self.number = new NSInteger;
    }
    return self;
}

- (instancetype)initWithNumber:(NSInteger)number {
    if (self = [super init]) {
        self.number = new NSInteger;
        memcpy(self.number, &number, sizeof(number));
    }
    return self;
}

- (void)dealloc {
    delete self.number;
    [super dealloc];
}

- (id)copyWithZone:(struct _NSZone *)zone {
    ObjCppClass *copy = static_cast<ObjCppClass *>([self.class new]);
    
    if (copy) {
        copy.number = self.number;
    }
    
    return copy;
}

@end
```

이제 `ObjCppClass`를 생성하고 복사하는 코드를 실행합니다.

```objc
int main(int argc, const char * argv[]) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    ObjCppClass *original = [[ObjCppClass alloc] initWithNumber:3];
    ObjCppClass *copy = [original copy];

    [original release];
    [copy release];

    [pool release];
    return 0;
}

```

그러면 마찬가지로 Runtime Error가 발생합니다.

```
malloc: *** error for object 0x600000004070: pointer being freed was not allocated
malloc: *** set a breakpoint in malloc_error_break to debug
```

이는 제가 `-[ObjCppClass copyWithZone:]`에서 포인터 주소만 복사했기 때문입니다. C++ 객체에서 했던 방법대로 메모리 주소를 새로 할당해야 합니다.

```objc
- (id)copyWithZone:(struct _NSZone *)zone {
    ObjCppClass *copy = static_cast<ObjCppClass *>([self.class new]);
    
    if (copy) {
        delete copy.number;
        copy.number = new NSInteger;
        memcpy(copy.number, self.number, sizeof(self.number));
    }
    
    return copy;
}
```

그러면 마찬가지로 문제가 해결됩니다.
