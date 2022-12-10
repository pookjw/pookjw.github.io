# [C++20] constexpr, consteval, constinit

C++20에서는 값을 다양한 방법으로 정의할 수 있다.

```cpp
int num = 3;
#define NUM 3
const int num = 3;
constexpr int num = 3;
constinit int num = 3;
constinit const int num = 3;

int sqr(int n) {
    return n * n;
}
#define SQRT(NUM) NUM * NUM
constexpr int sqr(int n) {
    return n * n;
}
consteval int sqr(int n) {
    return n * n;
}
```

이들의 차이점과 함께, 어떠한 성능 차이를 야기하는지에 대한 글이다.

## 변수

예를 들어 아래와 같은 코드가 있다고 하자. 실행해보면 9가 나온다.

```cpp
#include <iostream>

using namespace std;

int sqr(int n) {
    return n * n;
}

int num = 3;

int main(int argc, const char * argv[]) {
    if (num == 3) {
        cout << sqr(num) << endl; // 이게 불릴거임
    } else {
        cout << num << endl;
    }
    
    return 0;
}
```

lldb에서 보는 `main` 함수의 arm64 asm은 아래와 같다.

```
(lldb) disassemble -a 0x0000000100003d3c
MyScript`main:
->  0x100003d3c <+0>:   sub    sp, sp, #0x20
    0x100003d40 <+4>:   stp    x29, x30, [sp, #0x10]
    0x100003d44 <+8>:   add    x29, sp, #0x10
    0x100003d48 <+12>:  stur   wzr, [x29, #-0x4]
    0x100003d4c <+16>:  str    w0, [sp, #0x8]
    0x100003d50 <+20>:  str    x1, [sp]
    0x100003d54 <+24>:  adrp   x8, 5
    0x100003d58 <+28>:  ldr    w8, [x8]
    0x100003d5c <+32>:  subs   w8, w8, #0x3
    0x100003d60 <+36>:  b.ne   0x100003d94               ; <+88> at main.cpp
    0x100003d64 <+40>:  b      0x100003d68               ; <+44> at main.cpp
    0x100003d68 <+44>:  adrp   x8, 5
    0x100003d6c <+48>:  ldr    w0, [x8]
    0x100003d70 <+52>:  bl     0x100003d20               ; sqr at main.cpp:12
    0x100003d74 <+56>:  mov    x1, x0
    0x100003d78 <+60>:  adrp   x0, 1
    0x100003d7c <+64>:  ldr    x0, [x0, #0x30]
    0x100003d80 <+68>:  bl     0x100003f70               ; symbol stub for: std::__1::basic_ostream<char, std::__1::char_traits<char> >::operator<<(int)
    0x100003d84 <+72>:  adrp   x1, 0
    0x100003d88 <+76>:  add    x1, x1, #0xdf4            ; std::__1::endl<char, std::__1::char_traits<char> > at ostream:993
    0x100003d8c <+80>:  bl     0x100003dc8               ; std::__1::basic_ostream<char, std::__1::char_traits<char> >::operator<< at ostream:189
    0x100003d90 <+84>:  b      0x100003db8               ; <+124> at main.cpp
    0x100003d94 <+88>:  adrp   x8, 5
    0x100003d98 <+92>:  ldr    w1, [x8]
    0x100003d9c <+96>:  adrp   x0, 1
    0x100003da0 <+100>: ldr    x0, [x0, #0x30]
    0x100003da4 <+104>: bl     0x100003f70               ; symbol stub for: std::__1::basic_ostream<char, std::__1::char_traits<char> >::operator<<(int)
    0x100003da8 <+108>: adrp   x1, 0
    0x100003dac <+112>: add    x1, x1, #0xdf4            ; std::__1::endl<char, std::__1::char_traits<char> > at ostream:993
    0x100003db0 <+116>: bl     0x100003dc8               ; std::__1::basic_ostream<char, std::__1::char_traits<char> >::operator<< at ostream:189
    0x100003db4 <+120>: b      0x100003db8               ; <+124> at main.cpp
    0x100003db8 <+124>: mov    w0, #0x0
    0x100003dbc <+128>: ldp    x29, x30, [sp, #0x10]
    0x100003dc0 <+132>: add    sp, sp, #0x20
    0x100003dc4 <+136>: ret
```

`w8`에 `int num`을 load하고, `w8`에 3을 뺀 후에, 뺀 값이 0인지 아닌지 분기처리를 runtime에서 처리한다.

여기서 중요한 점은 분기처리하는 로직이 runtime에서 돌아가며 위 코드에서는 `cout << num << endl;`은 절대 불릴 일이 없는 코드이지만 asm에 정의된 것을 볼 수 있다. 이는 비효율적이다.

## define

이제 위에서 다룬 코드를 `define`으로 작성해보자.

```cpp
#include <iostream>

using namespace std;

#define NUM 3
#define SQRT(NUM) NUM * NUM

int main(int argc, const char * argv[]) {
#if NUM == 3
    cout << SQRT(NUM) << endl;
#else
    cout << NUM << endl;
#endif
    return 0;
}
```

lldb에서 보는 `main` 함수의 arm64 asm은 아래와 같다.

```
(lldb) disassemble -a 0x0000000100003d84
MyScript`main:
->  0x100003d84 <+0>:  sub    sp, sp, #0x30
    0x100003d88 <+4>:  stp    x29, x30, [sp, #0x20]
    0x100003d8c <+8>:  add    x29, sp, #0x20
    0x100003d90 <+12>: mov    w8, #0x0
    0x100003d94 <+16>: str    w8, [sp, #0xc]
    0x100003d98 <+20>: stur   wzr, [x29, #-0x4]
    0x100003d9c <+24>: stur   w0, [x29, #-0x8]
    0x100003da0 <+28>: str    x1, [sp, #0x10]
    0x100003da4 <+32>: adrp   x0, 1
    0x100003da8 <+36>: ldr    x0, [x0, #0x30]
    0x100003dac <+40>: mov    w1, #0x9
    0x100003db0 <+44>: bl     0x100003f78               ; symbol stub for: std::__1::basic_ostream<char, std::__1::char_traits<char> >::operator<<(int)
    0x100003db4 <+48>: adrp   x1, 0
    0x100003db8 <+52>: add    x1, x1, #0xdfc            ; std::__1::endl<char, std::__1::char_traits<char> > at ostream:993
    0x100003dbc <+56>: bl     0x100003dd0               ; std::__1::basic_ostream<char, std::__1::char_traits<char> >::operator<< at ostream:189
    0x100003dc0 <+60>: ldr    w0, [sp, #0xc]
    0x100003dc4 <+64>: ldp    x29, x30, [sp, #0x20]
    0x100003dc8 <+68>: add    sp, sp, #0x30
    0x100003dcc <+72>: ret  
```

3의 제곱의 값이 compime-time에서 미리 계산되어 `w1`에 `0x9`가 정의되며, 분기처리도 없고 `cout << NUM << endl;` 코드는 무시된 것이 보인다.

## const

const로 비슷한 코드를 짜보자

```cpp
#include <iostream>

using namespace std;

const int num = 3;
const int sqrt(int num) {
    return num * num;
}

int main(int argc, const char * argv[]) {
    if (num == 3) {
        cout << sqrt(num) << endl;
    } else {
        cout << num << endl;
    }
    
    return 0;
}
```

이것도 arm64 asm을 보면

```
(lldb) disassemble -a 0x0000000100003d74
MyScript`main:
->  0x100003d74 <+0>:  sub    sp, sp, #0x30
    0x100003d78 <+4>:  stp    x29, x30, [sp, #0x20]
    0x100003d7c <+8>:  add    x29, sp, #0x20
    0x100003d80 <+12>: mov    w8, #0x0
    0x100003d84 <+16>: str    w8, [sp, #0xc]
    0x100003d88 <+20>: stur   wzr, [x29, #-0x4]
    0x100003d8c <+24>: stur   w0, [x29, #-0x8]
    0x100003d90 <+28>: str    x1, [sp, #0x10]
    0x100003d94 <+32>: mov    w0, #0x3
    0x100003d98 <+36>: bl     0x100003d58               ; sqrt at main.cpp:13
    0x100003d9c <+40>: mov    x1, x0
    0x100003da0 <+44>: adrp   x0, 1
    0x100003da4 <+48>: ldr    x0, [x0, #0x30]
    0x100003da8 <+52>: bl     0x100003f70               ; symbol stub for: std::__1::basic_ostream<char, std::__1::char_traits<char> >::operator<<(int)
    0x100003dac <+56>: adrp   x1, 0
    0x100003db0 <+60>: add    x1, x1, #0xdf4            ; std::__1::endl<char, std::__1::char_traits<char> > at ostream:993
    0x100003db4 <+64>: bl     0x100003dc8               ; std::__1::basic_ostream<char, std::__1::char_traits<char> >::operator<< at ostream:189
    0x100003db8 <+68>: ldr    w0, [sp, #0xc]
    0x100003dbc <+72>: ldp    x29, x30, [sp, #0x20]
    0x100003dc0 <+76>: add    sp, sp, #0x30
    0x100003dc4 <+80>: ret 
```

`define`과 마찬가지로 분기처리하는 코드는 없으나, `sqrt`는 runtime에서 계산되는 것이 확인된다.

만약에 

```cpp
if (num == 3)
```

이 부분을

```cpp
const int a = 3;
if (num == a)
```

으로 바꾸면

```
(lldb) disassemble -a 0x0000000100003d70
MyScript`main:
->  0x100003d70 <+0>:  sub    sp, sp, #0x30
    0x100003d74 <+4>:  stp    x29, x30, [sp, #0x20]
    0x100003d78 <+8>:  add    x29, sp, #0x20
    0x100003d7c <+12>: mov    w8, #0x0
    0x100003d80 <+16>: str    w8, [sp, #0x8]
    0x100003d84 <+20>: stur   wzr, [x29, #-0x4]
    0x100003d88 <+24>: stur   w0, [x29, #-0x8]
    0x100003d8c <+28>: str    x1, [sp, #0x10]
    0x100003d90 <+32>: mov    w0, #0x3
    0x100003d94 <+36>: str    w0, [sp, #0xc]
    0x100003d98 <+40>: bl     0x100003d54               ; sqrt at main.cpp:13
    0x100003d9c <+44>: mov    x1, x0
    0x100003da0 <+48>: adrp   x0, 1
    0x100003da4 <+52>: ldr    x0, [x0, #0x30]
    0x100003da8 <+56>: bl     0x100003f70               ; symbol stub for: std::__1::basic_ostream<char, std::__1::char_traits<char> >::operator<<(int)
    0x100003dac <+60>: adrp   x1, 0
    0x100003db0 <+64>: add    x1, x1, #0xdf4            ; std::__1::endl<char, std::__1::char_traits<char> > at ostream:993
    0x100003db4 <+68>: bl     0x100003dc8               ; std::__1::basic_ostream<char, std::__1::char_traits<char> >::operator<< at ostream:189
    0x100003db8 <+72>: ldr    w0, [sp, #0x8]
    0x100003dbc <+76>: ldp    x29, x30, [sp, #0x20]
    0x100003dc0 <+80>: add    sp, sp, #0x30
    0x100003dc4 <+84>: ret 
```

메모리에 `a`라는 상수를 load하냐 마냐의 차이가 추가되며, 분기처리하는 코드는 여전히 없다.

하지만 변수와 비교할 경우 말이 달라진다.

```cpp
int a = 3;
if (num == a)
```

```
(lldb) disassemble -a 0x0000000100003d40
MyScript`main:
->  0x100003d40 <+0>:   sub    sp, sp, #0x30
    0x100003d44 <+4>:   stp    x29, x30, [sp, #0x20]
    0x100003d48 <+8>:   add    x29, sp, #0x20
    0x100003d4c <+12>:  stur   wzr, [x29, #-0x4]
    0x100003d50 <+16>:  stur   w0, [x29, #-0x8]
    0x100003d54 <+20>:  str    x1, [sp, #0x10]
    0x100003d58 <+24>:  mov    w8, #0x3
    0x100003d5c <+28>:  str    w8, [sp, #0xc]
    0x100003d60 <+32>:  ldr    w9, [sp, #0xc]
    0x100003d64 <+36>:  subs   w8, w8, w9
    0x100003d68 <+40>:  b.ne   0x100003d98               ; <+88> at main.cpp
    0x100003d6c <+44>:  b      0x100003d70               ; <+48> at main.cpp
    0x100003d70 <+48>:  mov    w0, #0x3
    0x100003d74 <+52>:  bl     0x100003d24               ; sqrt at main.cpp:13
    0x100003d78 <+56>:  mov    x1, x0
    0x100003d7c <+60>:  adrp   x0, 1
    0x100003d80 <+64>:  ldr    x0, [x0, #0x30]
    0x100003d84 <+68>:  bl     0x100003f70               ; symbol stub for: std::__1::basic_ostream<char, std::__1::char_traits<char> >::operator<<(int)
    0x100003d88 <+72>:  adrp   x1, 0
    0x100003d8c <+76>:  add    x1, x1, #0xdf4            ; std::__1::endl<char, std::__1::char_traits<char> > at ostream:993
    0x100003d90 <+80>:  bl     0x100003dc8               ; std::__1::basic_ostream<char, std::__1::char_traits<char> >::operator<< at ostream:189
    0x100003d94 <+84>:  b      0x100003db8               ; <+120> at main.cpp
    0x100003d98 <+88>:  adrp   x0, 1
    0x100003d9c <+92>:  ldr    x0, [x0, #0x30]
    0x100003da0 <+96>:  mov    w1, #0x3
    0x100003da4 <+100>: bl     0x100003f70               ; symbol stub for: std::__1::basic_ostream<char, std::__1::char_traits<char> >::operator<<(int)
    0x100003da8 <+104>: adrp   x1, 0
    0x100003dac <+108>: add    x1, x1, #0xdf4            ; std::__1::endl<char, std::__1::char_traits<char> > at ostream:993
    0x100003db0 <+112>: bl     0x100003dc8               ; std::__1::basic_ostream<char, std::__1::char_traits<char> >::operator<< at ostream:189
    0x100003db4 <+116>: b      0x100003db8               ; <+120> at main.cpp
    0x100003db8 <+120>: mov    w0, #0x0
    0x100003dbc <+124>: ldp    x29, x30, [sp, #0x20]
    0x100003dc0 <+128>: add    sp, sp, #0x30
    0x100003dc4 <+132>: ret  
```

`int a`는 변수이기 때문에, `if (num == a)`의 로직이 돌아가며 분기처리하는 코드가 그대로 담겨 있게 된다.

## constexpr

`constexpr`은 C++11에서 추가되었다. 상수를 정의할 수 있는 keyword이며 compile-time/runtime이 자동으로 결정된다.

아래처럼 코드를 짜보자

```cpp
#include <iostream>

using namespace std;

constexpr int num = 3;
constexpr int sqrt(int num) {
    return num * num;
}

int main(int argc, const char * argv[]) {
    if (num == 3) {
        constexpr int a = sqrt(num);
        cout << a << endl;
    } else {
        cout << num << endl;
    }
    
    return 0;
}
```

```
(lldb) disassemble -a 0x0000000100003d80
MyScript`main:
->  0x100003d80 <+0>:  sub    sp, sp, #0x30
    0x100003d84 <+4>:  stp    x29, x30, [sp, #0x20]
    0x100003d88 <+8>:  add    x29, sp, #0x20
    0x100003d8c <+12>: mov    w8, #0x0
    0x100003d90 <+16>: str    w8, [sp, #0x8]
    0x100003d94 <+20>: stur   wzr, [x29, #-0x4]
    0x100003d98 <+24>: stur   w0, [x29, #-0x8]
    0x100003d9c <+28>: str    x1, [sp, #0x10]
    0x100003da0 <+32>: mov    w1, #0x9
    0x100003da4 <+36>: str    w1, [sp, #0xc]
    0x100003da8 <+40>: adrp   x0, 1
    0x100003dac <+44>: ldr    x0, [x0, #0x30]
    0x100003db0 <+48>: bl     0x100003f78               ; symbol stub for: std::__1::basic_ostream<char, std::__1::char_traits<char> >::operator<<(int)
    0x100003db4 <+52>: adrp   x1, 0
    0x100003db8 <+56>: add    x1, x1, #0xdfc            ; std::__1::endl<char, std::__1::char_traits<char> > at ostream:993
    0x100003dbc <+60>: bl     0x100003dd0               ; std::__1::basic_ostream<char, std::__1::char_traits<char> >::operator<< at ostream:189
    0x100003dc0 <+64>: ldr    w0, [sp, #0x8]
    0x100003dc4 <+68>: ldp    x29, x30, [sp, #0x20]
    0x100003dc8 <+72>: add    sp, sp, #0x30
    0x100003dcc <+76>: ret 
```

분기처리하는 코드가 없으며, `<+32>`를 보면 3의 제곱의 값이 compile-time에서 미리 계산된 것을 볼 수 있다. 또한 `sqrt`에 breakpoint을 찍어도 pause가 걸리지 않는 것도 확인할 수 있다.

이제 아래 코드를

```cpp
constexpr int a = sqrt(num);
cout << a << endl;
```

이렇게 바꿔보자

```cpp
cout << sqrt(num) << endl;
```

```
(lldb) disassemble -a 0x0000000100003d54
MyScript`main:
->  0x100003d54 <+0>:  sub    sp, sp, #0x30
    0x100003d58 <+4>:  stp    x29, x30, [sp, #0x20]
    0x100003d5c <+8>:  add    x29, sp, #0x20
    0x100003d60 <+12>: mov    w8, #0x0
    0x100003d64 <+16>: str    w8, [sp, #0xc]
    0x100003d68 <+20>: stur   wzr, [x29, #-0x4]
    0x100003d6c <+24>: stur   w0, [x29, #-0x8]
    0x100003d70 <+28>: str    x1, [sp, #0x10]
    0x100003d74 <+32>: mov    w0, #0x3
    0x100003d78 <+36>: bl     0x100003da8               ; sqrt at main.cpp:13
    0x100003d7c <+40>: mov    x1, x0
    0x100003d80 <+44>: adrp   x0, 1
    0x100003d84 <+48>: ldr    x0, [x0, #0x30]
    0x100003d88 <+52>: bl     0x100003f6c               ; symbol stub for: std::__1::basic_ostream<char, std::__1::char_traits<char> >::operator<<(int)
    0x100003d8c <+56>: adrp   x1, 0
    0x100003d90 <+60>: add    x1, x1, #0xdf0            ; std::__1::endl<char, std::__1::char_traits<char> > at ostream:993
    0x100003d94 <+64>: bl     0x100003dc4               ; std::__1::basic_ostream<char, std::__1::char_traits<char> >::operator<< at ostream:189
    0x100003d98 <+68>: ldr    w0, [sp, #0xc]
    0x100003d9c <+72>: ldp    x29, x30, [sp, #0x20]
    0x100003da0 <+76>: add    sp, sp, #0x30
    0x100003da4 <+80>: ret 
```

아까랑 다른 결과가 나왔다. compile-time에서 3의 제곱이 미리 계산되지 않았으며 `sqrt`를 runtime에서 호출하는 모습을 볼 수 있다. 이는 `sqrt(num)`은 `constexpr`가 아닌 `const`로 해석되었기에 이런 결과가 나온 것이다.

또한 `constexpr`은 compile-time 코드만 정의할 수 있다.

```cpp
#include <iostream>

using namespace std;

constexpr int sqrt(int num) {
    return num * num;
}
int sqrt_runtime(int num) {
    return num * num;
}

constexpr int num = sqrt(3); // valid
constexpr int num_runtume = sqrt_runtime(3); // ERROR: Constexpr variable 'num_runtume' must be initialized by a constant expression

int main(int argc, const char * argv[]) {
    cout << num << endl;
    return 0;
}
```

## consteval

C++20에 추가된 keyword다. `consteval`은 함수를 무조건 compile-time에서만 돌아가게 할 수 있다.

```cpp
#include <iostream>

using namespace std;

constexpr int num = 3;
consteval int sqrt(int num) {
    return num * num;
}

int main(int argc, const char * argv[]) {
    if (num == 3) {
        cout << sqrt(num) << endl;
    } else {
        cout << num << endl;
    }
    
    return 0;
}
```

```
(lldb) disassemble -a 0x0000000100003d84
MyScript`main:
->  0x100003d84 <+0>:  sub    sp, sp, #0x30
    0x100003d88 <+4>:  stp    x29, x30, [sp, #0x20]
    0x100003d8c <+8>:  add    x29, sp, #0x20
    0x100003d90 <+12>: mov    w8, #0x0
    0x100003d94 <+16>: str    w8, [sp, #0xc]
    0x100003d98 <+20>: stur   wzr, [x29, #-0x4]
    0x100003d9c <+24>: stur   w0, [x29, #-0x8]
    0x100003da0 <+28>: str    x1, [sp, #0x10]
    0x100003da4 <+32>: adrp   x0, 1
    0x100003da8 <+36>: ldr    x0, [x0, #0x30]
    0x100003dac <+40>: mov    w1, #0x9
    0x100003db0 <+44>: bl     0x100003f78               ; symbol stub for: std::__1::basic_ostream<char, std::__1::char_traits<char> >::operator<<(int)
    0x100003db4 <+48>: adrp   x1, 0
    0x100003db8 <+52>: add    x1, x1, #0xdfc            ; std::__1::endl<char, std::__1::char_traits<char> > at ostream:993
    0x100003dbc <+56>: bl     0x100003dd0               ; std::__1::basic_ostream<char, std::__1::char_traits<char> >::operator<< at ostream:189
    0x100003dc0 <+60>: ldr    w0, [sp, #0xc]
    0x100003dc4 <+64>: ldp    x29, x30, [sp, #0x20]
    0x100003dc8 <+68>: add    sp, sp, #0x30
    0x100003dcc <+72>: ret 
```

`constexpr`와 다르게, `consteval`은 3의 제곱의 값을 compile-time에서 미리 계산된 것을 `<+40>`에서 볼 수 있다.

## constinit

C++20에 추가된 keyword다. 이름이 상수를 정의할 것 처럼 생겼지만 상수를 정의하는 용도가 아니다.

`constinit`은 값의 초기화되는 시점을 compile-time을 보장한다.

- `const`는 runtime 또는 compile-time이고, runtime 또는 compile-time에서 정의된 함수를 실행할 수 있으며

- `constexpr`도 runtime 또는 compile-time이지만, compile-time으로 정의된 함수만 실행할 수 있으며

- `constinit`은 compile-time이며 compile-time으로 정의된 함수만 실행할 수 있다. `consteval`은 함수에서 쓰인다면 `constinit`은 변수/상수에서 쓰인다.

```cpp
#include <iostream>

using namespace std;

constexpr int sqrt(int num) {
    return num * num;
}
int sqrt_runtime(int num) {
    return num * num;
}

constinit int num = sqrt(3); // valid
constinit int num_runtume = sqrt_runtime(3); // ERROR: Variable does not have a constant initializer

int main(int argc, const char * argv[]) {
    cout << num << endl;
    return 0;
}
```

`constinit`은 상수를 정의하는 기능이 아니므로, runtime에서 값을 변경할 수 있다.

```cpp
#include <iostream>

using namespace std;

constexpr int sqrt(int num) {
    return num * num;
}

constinit int num = sqrt(3); // valid

int main(int argc, const char * argv[]) {
    int a = 4;
    num = a;
    cout << num << endl;
    return 0;
}
```
