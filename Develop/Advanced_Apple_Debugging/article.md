[Advanced Apple Debugging & Reverse Engineering (raywenderlich.com)](https://www.raywenderlich.com/books/advanced-apple-debugging-reverse-engineering)의 내용을 정리한 글이다.

- [Chapter 1: Getting Started](#chapter-1)

- [Chapter 2: Help & Apropos](#chapter-2)

- [Chapter 3: Attaching with LLDB](#chapter-3)

- [Chapter 4: Stopping in Code](#chapter-4)

- [Chapter 5: Expression](#chapter-5)

- [Chapter 6: Thread, Frame & Stepping Around](#chapter-6)

- [Chapter 7: Image](#chapter-7)

# <a name="chapter-1">Chapeter 1: Getting Started</a>

```
(lldb) file /Applications/Xcode.app/Contents/MacOS/Xcode
Current executable set to '/Applications/Xcode.app/Contents/MacOS/Xcode' (arm64).
(lldb) process launch -e /dev/ttys001 --
Process 1809 launched: '/Applications/Xcode.app/Contents/MacOS/Xcode' (arm64)
```

이렇게 하면 lldb로 `Xcode`에 attach 및 실행을 할 수 있으며, 로그는 `/dev/ttys001`에 찍힌다. `Ctrl` + `C`를 누르면 pause를 할 수 있다.

```
(lldb) b -[NSView hitTest:]
Breakpoint 1: where = AppKit`-[NSView hitTest:], address = 0x00000001c74542d8
(lldb) c # 또는 continue
Process 1809 resuming
```

이렇게 되면 `-[NSView hitTest:]`에 breakpoint가 걸리며 실행될 때마다 아래처럼 pause가 걸린다.

```
Process 1809 stopped
* thread #1, queue = 'com.apple.main-thread', stop reason = breakpoint 1.1
    frame #0: 0x00000001c74542d8 AppKit` -[NSView hitTest:] 
AppKit`-[NSView hitTest:]:
->  0x1c74542d8 <+0>:  pacibsp 
    0x1c74542dc <+4>:  sub    sp, sp, #0x60
    0x1c74542e0 <+8>:  stp    x26, x25, [sp, #0x10]
    0x1c74542e4 <+12>: stp    x24, x23, [sp, #0x20]
    0x1c74542e8 <+16>: stp    x22, x21, [sp, #0x30]
    0x1c74542ec <+20>: stp    x20, x19, [sp, #0x40]
    0x1c74542f0 <+24>: stp    x29, x30, [sp, #0x50]
    0x1c74542f4 <+28>: add    x29, sp, #0x50
Target 0: (Xcode) stopped.
```

현재 멈춘 곳의 정보를 알기 위해서는 `po $rdi`라고 입력하면 된다던데... 이건 `x86_64` 기준 register이다. (`rdi`, `rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9`, ..., `r15`)

Apple Silicon 맥을 쓰는 유저라면 `arm64`이므로 register는 `x1`, `x2`, `x3`, ..., `x30`이 된다.

```
(lldb) po $rd1
error: expression failed to parse:
error: <user expression 1>:1:1: use of undeclared identifier '$rd1'
$rd1
^

(lldb) po $x0
<NSThemeFrame: 0x11c30f610>
```

이 상태에서 `continue`를 해도 계속 걸린다... `NSView`가 엄청나게 많은 구조여서 그런듯? 일단 pause가 계속 걸리는게 성가시니 지우자

```
(lldb) breakpoint delete
About to delete all breakpoints, do you want to do that?: [Y/n] y
All breakpoints removed. (1 breakpoint)
```

그리고 아래같은 새로운 breakpoint를 만들어준다. `-n`은 symbol 이름이며, `-C`는 breakpoint가 걸릴 때 실행할 명령어, `-G1`은 breapoint가 걸려도 pause하지 않겠다는 것이다. (`-G0`일 경우 pause한다.)

```
(lldb) breakpoint set -n "-[NSView hitTest:]" -C "po $x0" -G1
Breakpoint 2: where = AppKit`-[NSView hitTest:], address = 0x00000001c74542d8
```

이렇게 하고 `continue`를 하면 굉장히 많은 부분에서 breakpoint가 걸리며, `-C`가 실행되는 것을 볼 수 있다.

```
(lldb) c
Process 1809 resuming
(lldb)  po $x0
<NSTitlebarContainerView: 0x12662dab0>
(lldb)  po $x0
<DVTControllerContentView_ControlledBy_IDEWorkspaceTabController: 0x11c3bcc80>
(lldb)  po $x0
<NSView: 0x11c0148b0>
(lldb)  po $x0
<IDEWorkspaceDesignAreaSplitView:0x11c3bd9c0 delegate="(IDEWorkspaceDesignAreaSplitViewController)0x60000303d710" layout="constraints", dividers="views", arrangesAllSubviews="no">
```

이제 conditional breakpoint을 걸어본다. `-c`을 쓰면 할 수 있는데, 위에서 명령어를 실행하는 `-C`와 다른 것에 유의하자.

```
(lldb) breakpoint modify -c '(BOOL)[NSStringFromClass((id)[$x0 class]) containsString:@"IDESourceEditorView"]' -G0
```

이렇게 하면 Xcode에서 코드 입력창을 누를 때만 아래처럼 pause가 걸린다.

```
(lldb)  po $x0
IDESourceEditorView: Frame: (0.0, 0.0, 866.0, 900.0), Bounds: (0.0, 0.0, 866.0, 900.0) contentViewOffset: 0.0
Process 1809 stopped
* thread #1, queue = 'com.apple.main-thread', stop reason = breakpoint 2.1
    frame #0: 0x00000001c74542d8 AppKit` -[NSView hitTest:] 
AppKit`-[NSView hitTest:]:
->  0x1c74542d8 <+0>:  pacibsp 
    0x1c74542dc <+4>:  sub    sp, sp, #0x60
    0x1c74542e0 <+8>:  stp    x26, x25, [sp, #0x10]
    0x1c74542e4 <+12>: stp    x24, x23, [sp, #0x20]
    0x1c74542e8 <+16>: stp    x22, x21, [sp, #0x30]
    0x1c74542ec <+20>: stp    x20, x19, [sp, #0x40]
    0x1c74542f0 <+24>: stp    x29, x30, [sp, #0x50]
    0x1c74542f4 <+28>: add    x29, sp, #0x50
Target 0: (Xcode) stopped.
```

여기서 `p/x` 명령어로 breakpoint가 걸린 곳의 포인터 참조 주소를 알 수 있다.

```
(lldb) p/x $x0
(unsigned long) $192 = 0x0000000111ccf200
```

`po $x0` 했던 것 처럼, `po`에 참조 주소를 넣으면 해당 객체의 정보를 알 수 있다.

```
(lldb) po 0x0000000111ccf200
IDESourceEditorView: Frame: (0.0, 0.0, 866.0, 900.0), Bounds: (0.0, 0.0, 866.0, 900.0) contentViewOffset: 0.0
```

만약에 breakpoint가 걸린 `NSView`의 `isHidden` 상태를 바꾸고 싶다면 아래와 같이 하면 된다.

```
(lldb) po [$x0 setHidden:!(BOOL)[$x0 isHidden]]; [CATransaction flush]
 nil
```

마찬가지로 이런 식의 Selector 전송도 된다.

```
(lldb) po [$x0 string]
//
//  ViewController.swift
//  Hello Debugger
//
//  Created by Jinwoo Kim on 5/5/22.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

}



```

만약에 Swift로 하고 싶은 경우 우선 필요한 module들을 import해준다.

```
(lldb) ex -l swift -- import Foundation
(lldb) ex -l swift -- import AppKit
```

이런 식으로 Swift 코드를 실행할 수 있다.

```
(lldb) ex -l swift -o -- unsafeBitCast(0x0000000111ccf200, to: NSView.self)
IDESourceEditorView: Frame: (0.0, 0.0, 866.0, 900.0), Bounds: (0.0, 0.0, 866.0, 900.0) contentViewOffset: 0.0
```

이런 식으로 `insertText(_:)`라는 함수 실행도 되는데... `string`은 안 된다. 아마 `insertText(_:)`은 `NSView`의 method가 아니더라도 어딘가에서 저렇게 생긴 Selector가 존재해서 그거 가져다가 쓰는 것 같은데, `string`이란 Selector는 없어서 그런듯? `AnyObject`가 Selector dispatch하는 방식을 생각하면 이해가 될지도 모른다. [`perform(_:)`](https://developer.apple.com/documentation/objectivec/nsobjectprotocol/1418867-perform)을 쓰면 될 것 같기도...

```
(lldb) ex -l swift -o -- unsafeBitCast(0x0000000111ccf200, to: NSView.self).insertText("Yay! Swift!")
0 elements

(lldb) po [$x0 string]
//
//  ViewController.swift
//  Hello Debugger
//
//  Created by Jinwoo Kim on 5/5/22.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

}

Yay! Swift!

(lldb) ex -l swift -o -- unsafeBitCast(0x0000000111ccf200, to: NSView.self).string
error: expression failed to parse:
error: <EXPR>:3:52: error: value of type 'NSView' has no member 'string'
unsafeBitCast(0x0000000111ccf200, to: NSView.self).string
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ ^~~~~~
```

# <a name="chapter-2">Chapter 2: Help & Apropos</a>

`help` 명령어를 치면 무진장 많은 명령어들의 도움말들을 볼 수 있다.

```
(lldb) help
Debugger commands:
  apropos           -- List debugger commands related to a word or subject.
  breakpoint        -- Commands for operating on breakpoints (see 'help b' for shorthand.)
  command           -- Commands for managing custom LLDB commands.
  disassemble       -- Disassemble specified instructions in the current target.  Defaults to the
                       current function for the current thread and stack frame.
  expression        -- Evaluate an expression on the current thread.  Displays any returned value
                       with LLDB's default formatting.
  frame             -- Commands for selecting and examing the current thread's stack frames.
# 생략...

For more information on any command, type 'help <command-name>'.
```

이는 [DerekSelander/LLDB](https://github.com/DerekSelander/LLDB)을 `~/.lldbinit`에 설치했을 경우 그 명령어들의 도움말도 뜬다. 더 상세히 알고 싶으면 `help breakpoint`, `help breakpoint name` 이런 식으로 치면 된다.

```
(lldb) help breakpoint
Commands for operating on breakpoints (see 'help b' for shorthand.)

Syntax: breakpoint <subcommand> [<command-options>]

The following subcommands are supported:

      clear   -- Delete or disable breakpoints matching the specified source file and line.
      command -- Commands for adding, removing and listing LLDB commands executed when a breakpoint
                 is hit.
      delete  -- Delete the specified breakpoint(s).  If no breakpoints are specified, delete them
                 all.
      disable -- Disable the specified breakpoint(s) without deleting them.  If none are specified,
                 disable all breakpoints.
# 생략...

For more help on any particular subcommand, type 'help <command> <subcommand>'.
```

`apropos`를 쓸 경우 단어 검색이 가능하다.

```
(lldb) apropos swift
The following commands may relate to 'swift':
  swift             -- A set of commands for operating on the Swift Language Runtime.
  demangle          -- Demangle a Swift mangled name
  refcount          -- Inspect the reference count data for a Swift object
  swift-healthcheck -- Show the LLDB debugger health check diagnostics.
  dclass            -- Dumps info about objc/swift classes
# 생략...
```

만약에 reference count을 알아내는 명령어가 기억 안 난다! 싶으면 아래처럼 하면 `refcount`을 쓰면 된다는 것을 알 수 있다.

```
(lldb) apropos "reference count"
The following commands may relate to 'reference count':
  refcount -- Inspect the reference count data for a Swift object
```

# <a name="chapter-3">Chapter 3: Attaching with LLDB</a>

아래처럼 lldb에서 이미 실행된 프로세스에 attach 할 수 있다. (참고로 `pgrep -x Xcode` 명령어로 PID를 받아 올 수 있다.)

```
% lldb -n Xcode
(lldb) process attach --name "Xcode"

...

% lldb -p 3386
(lldb) process attach --pid 3386
```

만약 다음 번에 실행될 프로세스에 attach하고 싶은 경우, `-w` (`--waitFor`)를 쓰면 된다. 이럴 경우 파일 경로로 통해서도 설정할 수 있는데 이때는 `-w`가 필요 없다.

```
% lldb -n Finder -w
(lldb) process attach --name "Finder" --waitfor

...

% lldb -f /System/Library/CoreServices/Finder.app/Contents/MacOS/Finder
(lldb) target create "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"
Current executable set to '/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder' (arm64e).
```

`-f`을 통해 파일 경로로 지정했을 경우, `process launch` 명령어로 바로 실행시킬 수 있다.

```
(lldb) process launch
Process 3473 launched: '/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder' (arm64e)
```

아래 명령어로 설정된 target을 지울 수 있다.

```
(lldb) target delete
```

이제 `/bin/ls`를 통해 실행 중에 옵션을 넣는 방법에 대해 알자면, 일단 `/bin/ls`로 설정한 후

```
% lldb -f /bin/ls
(lldb) target create "/bin/ls"
Current executable set to '/bin/ls' (arm64e).
```

위에서 설명했듯이 `process launch`를 실행하면 해당 프로그램을 실행할 수 있다.

```
(lldb) process launch
Process 3502 launched: '/bin/ls' (arm64e)
Applications	Documents	Movies		Postman		git
Brewfile	Downloads	Music		Public		lldb_commands
Desktop		Library		Pictures	Sites		theos
Process 3502 exited with status = 0 (0x00000000) 
```

`-w` 옵션을 쓰면 `cd`를 한 다음에 프로그램을 실행하게 된다. 예를 들어 아래와 같이 명령어를 입력하면

```
(lldb) process launch -w /Applications
Process 3512 launched: '/bin/ls' (arm64e)

# /Applications의 내용...
```

아래와 같은 내용이라 할 수 있다.

```
% cd /Applications
% ls
```

`--` 옵션을 쓰면 프로그램 실행의 arguments를 지정할 수 있다.

```
(lldb) process launch -w /Applications
Process 3512 launched: '/bin/ls' (arm64e)

# /Applications의 내용...
```

이는 `% ls /Applications`와 같은거라 할 수 있다. 하지만 `--`는 아래이 `~` 문구가 같은 경우는 에러가 난다.

```
(lldb) process launch -- ~/Desktop
Process 3557 launched: '/bin/ls' (arm64e)
ls: ~/Desktop: No such file or directory
Process 3557 exited with status = 1 (0x00000001) 
```

이럴 경우 `-X true`를 써주면 된다.

```
(lldb) process launch -X true -- ~/Desktop
Process 3574 launched: '/bin/ls' (arm64e)

# ~/Desktop의 내용...
```

이는 `run` 명령어로도 할 수 있다.

```
(lldb) run ~/Desktop
Process 3583 launched: '/bin/ls' (arm64e)

# ~/Desktop의 내용...
```

만약에 현재 설정된 environment variable들을 보고 싶으면, `env` 명령어를 쓰면 된다.

```
(lldb) env
target.env-vars (dictionary of strings) =
```

책에서는 이런 식으로 environment variable을 설정할 수 있다는데... 내가 해보니 안 됨. shell이 달라서 그런듯...

```
(lldb) process launch -v LSCOLORS=Af -v CLICOLOR=1  -- /Applications/
```

이거는 터미널에서 아래 명령어와 같은거라 함.

```
$ LSCOLORS=Af CLICOLOR=1 ls /Applications/
```

만약에 출력 결과물을 파일로 저장하고 싶으면, `-o`를 쓰면 된다. 터미널에서 `>` 기호라고 생각하면 될듯하다.

```
(lldb) process launch -o /tmp/ls_output.txt -- /Applications
```

이러면 아래 터미널 명령어로 잘 저장되었는지 볼 수 있다.

```
% cat /tmp/ls_output.txt
```

`-i`을 쓰면 터미널의 `<` 기호같은 것을 쓸 수 있다.

```
(lldb) target create /usr/bin/wc

(lldb) process launch -i /tmp/ls_output.txt

(lldb) run
```

마지막 명령어의 경우 `wc`에 아무런 input이 없어서 멈출텐데, 해당 프로세스를 강제종로 시키고 싶으면 `Ctrl` + `D`를 누르면 된다.

# <a name="chapter-4">Chapter 4: Stopping in Code</a>

Symbol 검색하기

```
(lldb) image lookup -n "-[UIViewController viewDidLoad]"
1 match found in /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore:
        Address: UIKitCore[0x00000000004bd8d0] (UIKitCore.__TEXT.__text + 4957852)
        Summary: UIKitCore`-[UIViewController viewDidLoad]
```

정규식으로 Symbol 검색하기

```
(lldb) image lookup -rn test
1 match found in /Users/pookjw/Library/Developer/Xcode/DerivedData/Signals-byjsnxuqpxeyyddvxghkubpurqlj/Build/Products/Debug-iphonesimulator/Signals.app/Signals:
        Address: Signals[0x0000000100005e78] (Signals.__TEXT.__text + 15360)
        Summary: Signals`Signals.DetailViewController.test() throws -> () at DetailViewController.swift:52
```

Swift Symbol 검색하기

```
(lldb) image lookup -rn Signals.SwiftTestClass.name.setter
1 match found in /Users/pookjw/Library/Developer/Xcode/DerivedData/Signals-byjsnxuqpxeyyddvxghkubpurqlj/Build/Products/Debug-iphonesimulator/Signals.app/Signals:
        Address: Signals[0x000000010000b5fc] (Signals.__TEXT.__text + 37764)
        Summary: Signals`Signals.SwiftTestClass.name.setter : Swift.Optional<Swift.String> at SwiftTestClass.swift:32

(lldb) image lookup -rn Signals.SwiftTestClass.name.(getter|setter)
2 matches found in /Users/pookjw/Library/Developer/Xcode/DerivedData/Signals-byjsnxuqpxeyyddvxghkubpurqlj/Build/Products/Debug-iphonesimulator/Signals.app/Signals:
        Address: Signals[0x000000010000b58c] (Signals.__TEXT.__text + 37652)
        Summary: Signals`Signals.SwiftTestClass.name.getter : Swift.Optional<Swift.String> at SwiftTestClass.swift:32        Address: Signals[0x000000010000b5fc] (Signals.__TEXT.__text + 37764)
        Summary: Signals`Signals.SwiftTestClass.name.setter : Swift.Optional<Swift.String> at SwiftTestClass.swift:32
```

Swift Symbol로 breakpoint 걸기 (위에서 얻은 정확한 Symbol 이름을 넣어주면 된다)

```
(lldb) b Signals`Signals.SwiftTestClass.name.setter : Swift.Optional<Swift.String>
Breakpoint 3: where = Signals`Signals.SwiftTestClass.name.setter : Swift.Optional<Swift.String> at SwiftTestClass.swift:32, address = 0x00000001027d75fc
```

단축어로 breakpoint를 걸 수 있다.

```
(lldb) b -[UIViewController viewDidLoad]
Breakpoint 4: where = UIKitCore`-[UIViewController viewDidLoad], address = 0x000000018462b8d0

(lldb) b Signals.SwiftTestClass.name.setter : Swift.Optional<Swift.String>
Breakpoint 5: where = Signals`Signals.SwiftTestClass.name.setter : Swift.Optional<Swift.String> at SwiftTestClass.swift:32, address = 0x00000001027d75fc
```

정규식을 통해서도 걸 수 있다.

```
(lldb) rb SwiftTestClass.name.setter
Breakpoint 6: where = Signals`Signals.SwiftTestClass.name.setter : Swift.Optional<Swift.String> at SwiftTestClass.swift:32, address = 0x00000001027d75fc

(lldb) rb name\.setter
Breakpoint 7: 8 locations.

(lldb) rb '\-\[UIViewController\ '
Breakpoint 8: 796 locations.

# Category들만
(lldb) rb '\-\[UIViewController(\(\w+\))?\ '
Breakpoint 9: 796 locations.

# DetailViewController.swift 안에 있는 모드 코드에
(lldb) rb . -f DetailViewController.swift
Breakpoint 10: 65 locations.

# 모든 Symbol에 breakpoint 걸기...
(lldb) rb .

# 특정 Module에 있는 모든 Symbol에 breakpoint 걸기...
(lldb) rb . -s Commons
(lldb) rb . -s UIKitCore
```

만약에 breakpoint가 몇번 이상 걸리면 자동으로 delete되게 처리하려면 `-o` (one-shot)을 쓰면 된다.

```
(lldb) rb . -s UIKitCore -o 1
```

breakpoint 명령어들 예제를 적자면

```
# Commons moudle 안의 Swift 언어로 된 모든 Symbol들에 breakpoint를 건다.
(lldb) breakpoint set -L swift -r . -s Commons

# 모든 소스코드 파일 (-A)에서 "if let"이 포함되어 있으면 breakpoint를 건다.
(lldb) breakpoint set -A -p "if let"

# 특정 파일만 하고 싶으면
(lldb) breakpoint set -p "if let" -f MasterViewController.swift -f DetailViewController.swift

# Signals model 안에 있는 모든 소스코드에서 "if let"이 포함되어 있는 곳에 breakpoint를 건다.
(lldb) breakpoint set -p "if let" -s Signals -A

# `-[UIViewController viewDidLoad]`가 걸리면 명령어를 실행하고 pause하지 않는다.
(lldb) breakpoint set -n "-[UIViewController viewDidLoad]` -C "po $arg1" -G1
```

여담으로 디버깅 결과물들을 파일로 쓸 수 있다.

```
(lldb) breakpoint write -f /tmp/br.json
(lldb) platform shell cat /tmp/br.json

# re-import
(lldb) breakpoint read -f /tmp/br.json
```

현재 설정된 breakpoint 목록보기

```
# 전체 breakpoint
(lldb) breakpoint list

# 첫번째꺼만
(lldb) breakpoint list 1

# 간략하게 (briefly)
(lldb) breakpoint list 1 -b

# 첫번째꺼의 첫번째 symbol만
(lldb) breakpoint list 1.1

# 특정 breakpoint만 지우기
(lldb) breakpoint delete 1
(lldb) breakpoint delete 1.1
```

# <a name="chapter-5">Chapter 5: Expression</a>

`NSObject.description`을 override 해보면

```swift
override var description: String {
  return "Yay! debugging " + super.description
}
```

`print("\(self)")`로 찍어보면 위에서 정의한 `description`이 나오는 것을 확인할 수 있다.

```
Yay! debugging <Signals.MasterViewController: 0x7f8a0ac06b70>
```

마찬가지로 lldb에서 `po self`를 하면 똑같이 나온다.

```
(lldb) po self
Yay! debugging <Signals.MasterViewController: 0x7f8a0ac06b70>
```

이제 `NSObject.debugDescription`을 override 해보면

```swift
override var debugDescription: String {
  return "debugDescription: " + super.debugDescription
}
```

`print(_:)`에서는 여전히 `description`이 나오지만, `po self`에서는 `debugDescription`이 나오는 것을 확인할 수 있다.

```
(lldb) po self
debugDescription: Yay! debugging <Signals.MasterViewController: 0x7fb71fd04080>
```

이제 `p self`를 해보면 raw를 볼 수 있다.

```
(lldb) p self
(Signals.MasterViewController) $R0 = 0x0000000149615e70 {
  UIKit.UITableViewController = {
    baseUIViewController@0 = {
      baseUIResponder@0 = {
        baseNSObject@0 = {
          isa = Signals.MasterViewController
        }
      }
      _overrideTransitioningDelegate = 0x0000000000000000
      _view = some {
        some = 0x000000014a02ee00 {
          baseUIScrollView@0 = {
            baseUIView@0 = {

# 생략...
```

또한 `po`나 `p`가 불릴 경우, 출력의 메모리 주소는 `$R0`, `$R1`, `$R2`... 이런 식으로 register에 저장되며, `continue`가 되면 다 날라간다.

```
(lldb) p self
(Signals.MasterViewController) $R0 = 0x00000001286053c0 {
# 생략

(lldb) p self
(Signals.MasterViewController) $R1 = 0x00000001286053c0 {
# 생략

(lldb) p self
(Signals.MasterViewController) $R2 = 0x00000001286053c0 {
# 생략

(lldb) po self
debugDescription: Yay! debugging <Signals.MasterViewController: 0x1286053c0>

(lldb) p self
(Signals.MasterViewController) $R4 = 0x00000001286053c0 {
# 생략

(lldb) po $R5
debugDescription: Yay! debugging <Signals.MasterViewController: 0x1286053c0>

(lldb) po $R6
debugDescription: Yay! debugging <Signals.MasterViewController: 0x1286053c0>
```

또한 `type` 명령어로 통해 `p`에서 나오는 결과를 커스텀 할 수 있다.

```
(lldb) type summary add Signals.MasterViewController --summary-string "Wahho!"
(lldb) p self
(Signals.MasterViewController) $R8 = 0x00000001286053c0 Wahho!

# 초기화
(lldb) type summary clear
```

`po`에 대해 좀 더 알아보자면, `po`는 코드 실행도 가능하다. 다만 현재 context 언어 (Swift, Objective-C)에 맞게 써야 한다.


- Swift Context

```
(lldb) po [UIApplication sharedApplication]
error: expression failed to parse:
error: <EXPR>:8:16: error: expected ',' separator
[UIApplication sharedApplication]
               ^
              ,

(lldb) po UIApplication.shared
<UIApplication: 0x1485042c0>
```

- Objective-C Context

```
(lldb) po [UIApplication sharedApplication]
<UIApplication: 0x1485042c0>

(lldb) po UIApplication.shared
error: expression failed to parse:
error: No module map file in /Users/pookjw/Library/Developer/Xcode/DerivedData/Signals-cwkqbgfljqhkztfcsvolnunfygne/Build/Products/Debug-iphonesimulator/Commons.framework

error: <user expression 2>:1:15: property 'shared' not found on object of type 'UIApplication'
UIApplication.shared
```

Context에 상관 없이 특정 언어를 지정해서 실행할 수도 있다.

```
(lldb) expression -l objc -O -- [UIApplication sharedApplication]
<UIApplication: 0x1485042c0>

(lldb) expression -l swift -O -- UIApplication.shared
<UIApplication: 0x1485042c0>
```

`expression`의 `-O`는 아래와 같다.

```
-O ( --object-description )
            Display using a language-specific description API, if possible.
```

변수를 선언할 수도 있다. 물론 ARC는 안 된다.

```
# 이렇게 하면 안 된다.
(lldb) po id test = [NSObject new]
(lldb) po test
error: use of undeclared identifier 'test

# 이렇게 해야 한다.
(lldb) po id $test = [NSObject new]
(lldb) po $test
<NSObject: 0x600000718100>

(lldb) po [$test release]
0x0000000104af8000

# Swift에서...
(lldb) po id $test = [NSObject new]
(lldb) expression -l swift -O -- $test
<NSObject: 0x600000f580c0>

# 이런건 아직 안 되는듯? Bridging이 생각하는 것 처럼 되진 않는다 함
(lldb) expression -l swift -O -- $test.description
error: expression failed to parse:
error: <EXPR>:3:1: error: cannot find '$test' in scope
$test.description
^~~~~
```

`expression`의 `-i` 플래그에 대해서도 알아보자. `expression`을 통해 명령어가 실행됐을 때, 그 명령어를 현재 breakpoint에도 걸리게 할지를 정할 수 있다.

```
-i <boolean> ( --ignore-breakpoints <boolean> )
            Ignore breakpoint hits while running expressions
```

```
# `-[UIViewController viewDidLoad]`에 breakpoint를 설정한다.
(lldb) b -[UIViewController viewDidLoad]
Breakpoint 3: where = UIKitCore`-[UIViewController viewDidLoad], address = 0x000000018462b8d0

# `-i` 플래그를 안 쓰면 위에서 정의한 breakpoint가 기본적으로 무시된다.
(lldb) expression -l swift -O -- self.viewDidLoad()
Yay! debugging <Signals.MasterViewController: 0x135510060>
0 elements

# 하지만 `-i 0`으로 설정하면 breakpoint 때문에 에러가 난다.
(lldb) expression -l swift -O -i 0 -- self.viewDidLoad()
error: Execution was interrupted, reason: breakpoint 3.1.
The process has been left at the point where it was interrupted, use "thread return -x" to return to the state before expression evaluation.
```

마지막으로 `expression`은 format을 지정해서 출력할 수 있다. 예를 들어, `-G`의 경우 GDB format이다. 이건 지엽적이라 그냥 책을 보고 공부하자.

```
(lldb) expression -G x -- 10
(int) $0 = 0x0000000a
```

# <a name="chapter-6">Chapter 6: Thread, Frame & Stepping Around</a>

[Stack과 Heap](https://sklubmk.github.io/2021/11/01/0a6d4d441931/)

lldb로 backtrace를 볼 수 있다.

```
(lldb) b Signals.MasterViewController.viewWillAppear(Swift.Bool) -> ()
Breakpoint 2: where = Signals`Signals.MasterViewController.viewWillAppear(Swift.Bool) -> () at MasterViewController.swift:53, address = 0x0000000104c0ad44
(lldb) c
Process 19367 resuming

# breakpoint가 걸리면

# backtrace 보기
(lldb) thread backtrace
* thread #1, queue = 'com.apple.main-thread', stop reason = breakpoint 2.1
  * frame #0: 0x0000000104c0ad44 Signals`MasterViewController.viewWillAppear(animated=false, self=0x0000000000000000) at MasterViewController.swift:53
    frame #1: 0x0000000104c0b27c Signals`@objc MasterViewController.viewWillAppear(_:) at <compiler-generated>:0
    frame #2: 0x0000000184631720 UIKitCore`-[UIViewController _setViewAppearState:isAnimating:] + 604

# 현재 frame 정보
(lldb) frame info
frame #0: 0x0000000104c0ad44 Signals`MasterViewController.viewWillAppear(animated=false, self=0x0000000000000000) at MasterViewController.swift:53

# Thread 목록 보기
(lldb) thread list
Process 19367 stopped
* thread #1: tid = 0x72601, 0x0000000104c0ad44 Signals`MasterViewController.viewWillAppear(animated=false, self=0x0000000000000000) at MasterViewController.swift:53, queue = 'com.apple.main-thread', stop reason = breakpoint 2.1
  thread #2: tid = 0x726ad, 0x00000001cba33ce4 libsystem_kernel.dylib`__workq_kernreturn + 8
  thread #3: tid = 0x726ae, 0x00000001cba888fc libsystem_pthread.dylib`start_wqthread

# Thread 변경
(lldb) thread select 7
(lldb) thread backtrace
* thread #7, queue = 'com.apple.UIKit.KeyboardManagement'
  * frame #0: 0x00000001cba33dd4 libsystem_kernel.dylib`__ulock_wait + 8
    frame #1: 0x0000000104ff25fc libdispatch.dylib`_dlock_wait + 52
    frame #2: 0x0000000104ff23ac libdispatch.dylib`_dispatch_thread_event_wait_slow + 52

# frame 변경
(lldb) frame select 10
frame #10: 0x00000001809258d8 Foundation`__88-[NSXPCConnection _sendInvocation:orArguments:count:methodSignature:selector:withProxy:]_block_invoke_3 + 208
Foundation`__88-[NSXPCConnection _sendInvocation:orArguments:count:methodSignature:selector:withProxy:]_block_invoke_3:
->  0x1809258d8 <+208>: b      0x180925c38               ; <+1072>
    0x1809258dc <+212>: adrp   x8, 385088
    0x1809258e0 <+216>: ldr    x8, [x8, #0xf50]
    0x1809258e4 <+220>: cmp    x21, x8
    0x1809258e8 <+224>: b.eq   0x1809259dc               ; <+468>
    0x1809258ec <+228>: adrp   x8, 385088
    0x1809258f0 <+232>: ldr    x8, [x8, #0xf58]
    0x1809258f4 <+236>: cmp    x21, x8
(lldb) frame info
frame #10: 0x00000001809258d8 Foundation`__88-[NSXPCConnection _sendInvocation:orArguments:count:methodSignature:selector:withProxy:]_block_invoke_3 + 208
```

step은 아래처럼 할 수 있다.

```
# 둘이 같은듯? 코드를 step 할 수 있음
(lldb) next
(lldb) step -a 1

# 얘는 Assembly를 step
(lldb) step
(lldb) step -a 0

# Assembly step을 끝냄 (코드 step으로 돌아가는거임)
(lldb) finish
```

현재 frame에 존재하는 변수들 알아볼 수 있다. Xcode에서 뜨는거랑 같은 원리.

```
(lldb) frame variable
(Bool) animated = false
(Signals.MasterViewController) self = 0x0000000137d27740 {
  UIKit.UITableViewController = {
    baseUIViewController@0 = {
      baseUIResponder@0 = {
        baseNSObject@0 = {
          isa = Signals.MasterViewController
        }
      }
# 생략...

# Flat하게 보기
(lldb) frame variable -F
animated._value = 0
self = 0x0000000137d27740
self =
self.isa = Signals.MasterViewController
self._overrideTransitioningDelegate = 0x0000000000000000
self._view = some
# 생략...

# 특정 이름만 보기
(lldb) frame variable -F animated
animated._value = 0

(lldb) frame variable -F self
self = 0x0000000137d27740
self =
self.isa = Signals.MasterViewController
self._overrideTransitioningDelegate = 0x0000000000000000
self._view = some
self._view.some = 0x0000000140851400
self._view.some.isa = UITableView
# 생략...
```

# <a name="chapter-7">Chapter 7: Image</a>

현재 load된 Image 목록을 아래처럼 알아낼 수 있다.

```
(lldb) image list
[  0] 73AB11C0-1DF9-3381-87D6-C9CF673C054C 0x0000000104c08000 /Users/pookjw/Library/Developer/Xcode/DerivedData/Signals-akjtdbeivvcitldylztlxnerzrbj/Build/Products/Debug-iphonesimulator/Signals.app/Signals 
[  1] F82A5CF7-0669-37E6-949A-963C97AA692C 0x0000000104f38000 /usr/lib/dyld 
[  2] 6E6188A1-7B04-3AE8-BE81-CB35B05B8358 0x0000000104e50000 /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot/usr/lib/dyld_sim 
# 생략...

(lldb) image list Foundation
[  0] C5E56BF5-55BE-3ABB-947C-CDC542A7B3B5 0x00000001806fd000 /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/Foundation.framework/Foundation 
```

모든 symbol을 dump 뜰 수도 있다.

```
(lldb) image dump symtab UIKitCore -s address
Symtab, file = /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore, num_symbols = 167998 (sorted by address):
               Debug symbol
               |Synthetic symbol
               ||Externally Visible
               |||
Index   UserID DSX Type            File Address/Value Load Address       Size               Flags      Name
------- ------ --- --------------- ------------------ ------------------ ------------------ ---------- ----------------------------------
[    0]      0     Code            0x0000000000003234 0x0000000184171234 0x0000000000000168 0x000e0000 -[UIColorWell _commonInit]
[    1]      1     Code            0x000000000000339c 0x000000018417139c 0x0000000000000058 0x000e0000 -[UIColorWell initWithFrame:]

# 생략...
```

symbol을 검색할 수도 있다.

```
(lldb) image lookup -n "-[UIViewController viewDidLoad]"
1 match found in /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore:
        Address: UIKitCore[0x00000000004bd8d0] (UIKitCore.__TEXT.__text + 4957852)
        Summary: UIKitCore`-[UIViewController viewDidLoad]

(lldb) image lookup -rn '\[UIViewController\ '
843 matches found in /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore:
        Address: UIKitCore[0x00000000004b16c8] (UIKitCore.__TEXT.__text + 4908180)
        Summary: UIKitCore`-[UIViewController _presentationControllerClassName]        Address: UIKitCore[0x00000000004b16e8] (UIKitCore.__TEXT.__text + 4908212)
        Summary: UIKitCore`-[UIViewController navigationInsetAdjustment]        Address: UIKitCore[0x00000000004b1734] (UIKitCore.__TEXT.__text + 4908288)
# 생략...
```

Type의 정보를 알아낼 수도 있다.

```
# C 구조체
(lldb) image lookup -t sigaction
Best match found in /Users/pookjw/Library/Developer/Xcode/DerivedData/Signals-akjtdbeivvcitldylztlxnerzrbj/Build/Products/Debug-iphonesimulator/Signals.app/Signals:
id = {0x000057ee}, name = "sigaction", byte-size = 16, decl = signal.h:286, compiler_type = "struct sigaction {
    __sigaction_u __sigaction_u;
    sigset_t sa_mask;
    int sa_flags;
}"

(lldb) image lookup -t NSObject
Best match found in /Users/pookjw/Library/Developer/Xcode/DerivedData/Signals-akjtdbeivvcitldylztlxnerzrbj/Build/Products/Debug-iphonesimulator/Signals.app/Signals:
id = {0x000002b8}, name = "NSObject", byte-size = 8, decl = NSObject.h:53, compiler_type = "@interface NSObject{
    Class isa;
}
@end"
```

또한 `NSObject(IvarDescription)` Category에는 재밌는 것들이 있는데,

```
(lldb) image lookup -rn NSObject\(IvarDescription\)
7 matches found in /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore:
        Address: UIKitCore[0x0000000001002368] (UIKitCore.__TEXT.__text + 16773428)
        Summary: UIKitCore`-[NSObject(IvarDescription) __ivarDescriptionForClass:]        Address: UIKitCore[0x000000000100251c] (UIKitCore.__TEXT.__text + 16773864)
        Summary: UIKitCore`-[NSObject(IvarDescription) _ivarDescription]        Address: UIKitCore[0x000000000100262c] (UIKitCore.__TEXT.__text + 16774136)
        Summary: UIKitCore`-[NSObject(IvarDescription) __propertyDescriptionForClass:]        Address: UIKitCore[0x0000000001002ab0] (UIKitCore.__TEXT.__text + 16775292)
        Summary: UIKitCore`-[NSObject(IvarDescription) _propertyDescription]        Address: UIKitCore[0x0000000001002ba8] (UIKitCore.__TEXT.__text + 16775540)
        Summary: UIKitCore`-[NSObject(IvarDescription) __methodDescriptionForClass:]        Address: UIKitCore[0x0000000001003088] (UIKitCore.__TEXT.__text + 16776788)
        Summary: UIKitCore`-[NSObject(IvarDescription) _methodDescription]        Address: UIKitCore[0x0000000001003180] (UIKitCore.__TEXT.__text + 16777036)
        Summary: UIKitCore`-[NSObject(IvarDescription) _shortMethodDescription]
```

요약하면 `_ivarDescription`으로 ivar들을 볼 수 있다. 예를 들어 `UIApplication` 같은 경우

```
(lldb) po [[UIApplication sharedApplication] _ivarDescription]
<UIApplication: 0x15e504610>:
in UIApplication:
	_delegate (<UIApplicationDelegate>*): <Signals.AppDelegate: 0x600002d610a0>
	_remoteControlEventObservers (long): 0
	_topLevelNibObjects (NSArray*): nil
	_networkResourcesCurrentlyLoadingCount (long): 0
	_hideNetworkActivityIndicatorTimer (NSTimer*): nil
	_editAlertController (UIAlertController*): nil
	_statusBar (UIStatusBar*): nil
	_statusBarRequestedStyle (long): 0
	_statusBarWindow (UIStatusBarWindow*): nil
# 생략
```

이런 재밌는 정보들이 나온다. `UIStatusBar`는 iOS 13 이후로 `UIScene`의 등장에 따라 사라진 것 같다.

```
(lldb) po [UIApplication sharedApplication]->_statusBar
 nil
```

