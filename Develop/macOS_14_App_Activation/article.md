# [macOS 14] 새로운 App Activation 방식

macOS 14 부터 App Activation의 로직이 바뀌었습니다. 이전 로직은 사용자 경험을 해쳤기 때문입니다.

만약에 사용자가 영화를 보고 있거나 발표를 하고 있다던지 무언가에 집중하고 있다고 가정합시다. 그 상황에서 다른 앱에 갑자기 화면상에 켜지거나 (activate), 다른 앱이 갑자기 파일을 열어 버려서 새로운 앱이 화면에 켜지는 일이 발생했습니다. 특히 악성 프로그램들이 이 정책을 악용하고 있었습니다.

이러한 불쾌한 경험을 막기 위해, 현재 Activate된 앱만 다른 앱을 Activate 할 수 있도록 정책이 바뀌었습니다.

모든 정책은 SkyLight (WindowServer)에서 관리합니다.

## API

### Deprecated

- [`NSApplicationActivateIgnoringOtherApps`](https://developer.apple.com/documentation/appkit/nsapplicationactivationoptions/nsapplicationactivateignoringotherapps) : 사용자에게 불쾌한 경험을 주게 하는 option이었습니다. 이는 deprecated 됩니다.

### Added

- [`-[NSRunningApplication activateFromApplication:options:]`](https://developer.apple.com/documentation/appkit/nsrunningapplication/4168356-activatefromapplication) : parameter의 application이 activate 상태이거나 yield 받은 상태일 경우, `NSRunningApplication`을 activate

- [`-[NSApplication activate]`](https://developer.apple.com/documentation/appkit/nsapplication/4168336-activate) : 현재 App을 Activate - Activate된 앱에서 yield 받았을 때만 유효

- [`-[NSApplication yieldActivationToApplication:]`](https://developer.apple.com/documentation/appkit/nsapplication/4168338-yieldactivationtoapplication), [`-[NSApplication yieldActivationToApplicationWithBundleIdentifier:]`](https://developer.apple.com/documentation/appkit/nsapplication/4168339-yieldactivationtoapplicationwith) : 만약 현재 App이 Activate되었다면, Activate 권한을 다른 App에 양보. 양보한 상태에서도 현재 App은 Activate를 전환할 수 있는 권한을 지닙니다.
