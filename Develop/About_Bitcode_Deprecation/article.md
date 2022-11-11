# LLVM에서 Bitcode의 deprecation에 대해

Xcode 14 부터 Bitcode는 deprecated되며 개인적인 생각을 정리한 글입니다.

## Bitcode의 목적

- iOS 7 이전에는 armv6/armv7/armv7s 아키텍쳐만 지원했던 것에 비해, iPhone 5s가 등장하면서 iOS 7 부터는 arm64/arm64e가 iOS에 등장했고 Apple Watch도 64비트를 지원하면서 arm64_32라는 아키텍쳐도 등장했는데 아마 저전력 때문으로 보입니다.

- 이렇게 하나의 앱 바이너리에 여러가지 아키텍쳐가 지원하면 앱 용량이 커지기에, 아키텍쳐 별로 앱 바이너리를 쪼개서 용량을 아끼는 Bitcode 기술이 등장합니다.

## Bitcode가 사라져야 하는 이유

- 하지만 iOS에서 32비트 지원은 iOS 11에서 끊겼고, 올해 watchOS 9 부터 Apple Watch Series 3도 지원이 끊겨서 더 이상 armv6/armv7/armv7s 지원은 사라졌습니다. iOS에서는 arm64/arm64e watchOS에서는 arm64_32만 지원하는 상태이기에, Bitcode의 큰 의미가 사라진 상태입니다.

- 애플 입장에서 Bitcode를 지속할 경우 LLVM의 유지보수가 힘듭니다.

- 개발자가 assembly 코드를 직접 작성할 경우 Bitcode를 지원하지 않습니다. 금융 앱 (신한 시리즈)의 경우 보안을 위해 syscall 호출을 안하고, 커널에 함수 호출을 직접 하기 위해 assembly 코드를 작성하는 경우가 있습니다.

## RISC-V가 도입된다는 루머가 있던데?

- RISC-V가 도입되면 Bitcode 기술이 다시 등장할 수도 있고, 애플이 그동안 Bitcode를 골치거리로 여겨왔다면 등장하지 않을거고 그러면 앱 용량이 다시 한 번 더 커질겁니다.

- 제 생각에는 아마 Bitcode는 다시 도입되지 않을거에요. Apple Silicon이 등장하면서 macOS에 Bitcode 대신에 Universal Binary가 등장한게 그 증거에요. 덕분에 M1 칩이 나온 이래로 대부분의 앱 용량이 커졌죠.
