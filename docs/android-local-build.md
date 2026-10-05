# Local Android build environment

Recorded on 2026-10-04 for the macOS development host. This document describes
the isolated toolchain and the observed build progress. The current APK outcome
and remaining verification limits are recorded in [validation.md](validation.md).

## Toolchain and writable paths

Tool installations and user-level dependency caches are kept under
`/Users/mylxsw/Workspace/.tools`. The commands below set environment variables
for the current shell only; they do not change shell startup files, system Java,
the Homebrew SDK, or global Flutter configuration. Normal project build outputs
remain in the repository.

| Component | Local path / version |
| --- | --- |
| Flutter | `.tools/flutter-typeflux`, version 3.47.2 |
| Java | `.tools/typeflux-jdk/jdk-21.0.12.1+1/Contents/Home`, Eclipse Temurin 21.0.12.1+1 |
| Android SDK | `.tools/typeflux-android-sdk` |
| NDK | `ndk/28.2.13676358`, Android NDK r28c |
| Android platforms | `platforms/android-36`; `platforms/android-35` was also installed during native plugin configuration |
| Android build tools | `build-tools/36.0.0` |
| Gradle user home | `.tools/gradle` |
| Dart / Flutter package cache | `.tools/pub-cache` |
| Android user home for the build | `.tools/typeflux-android-userhome` |

The JDK was downloaded from the official
[Eclipse Temurin release](https://github.com/adoptium/temurin21-binaries/releases/tag/jdk-21.0.12.1%2B1).
Its archive SHA-256 was verified before extraction. `java -version` confirmed
Temurin 21.0.12.1+1. Gradle 9.3.1 is the project's wrapper version; Java 21 is
within its supported runtime range. See the official
[Gradle Java compatibility table](https://docs.gradle.org/current/userguide/compatibility.html).

The writable SDK reuses the existing SDK at
`/opt/homebrew/share/android-commandlinetools` without modifying it:

- `cmdline-tools` and the seven existing license files were copied locally.
- `platforms` and `build-tools` are writable parent directories. Their original
  `android-36` and `36.0.0` version directories are individual symbolic links to
  the existing SDK, so later version installations can write into the local SDK.
- Existing `platform-tools` and `emulator` directories are linked to that SDK.
- NDK `28.2.13676358` was installed into the writable root using its local
  `sdkmanager`. Installation returned exit code 0; `source.properties` confirms
  r28c, and the installed Clang reports version 19.0.1.
- A native JNI plugin additionally required platform 35. Its automatic
  installation completed during the build. This does not replace platform 36.

The copied license files remained byte-identical to the originals after the
explicit NDK installation. No new license acceptance was submitted. CMake 3.22.1 was later installed
automatically during the successful native build using the existing licenses.

## Reproduce the environment

Run these commands from a shell on the same development machine. Adjust
`TYPEFLUX_WORKSPACE` if the checkout and tool directory move together.

```sh
export TYPEFLUX_WORKSPACE=/Users/mylxsw/Workspace
export TYPEFLUX_TOOLS="$TYPEFLUX_WORKSPACE/.tools"
export JAVA_HOME="$TYPEFLUX_TOOLS/typeflux-jdk/jdk-21.0.12.1+1/Contents/Home"
export ANDROID_HOME="$TYPEFLUX_TOOLS/typeflux-android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_USER_HOME="$TYPEFLUX_TOOLS/typeflux-android-userhome"
export GRADLE_USER_HOME="$TYPEFLUX_TOOLS/gradle"
export PUB_CACHE="$TYPEFLUX_TOOLS/pub-cache"
export ANALYZER_STATE_LOCATION_OVERRIDE="$TYPEFLUX_TOOLS/analyzer"
export XDG_CONFIG_HOME="$TYPEFLUX_TOOLS/config"
export FLUTTER_SUPPRESS_ANALYTICS=true
export PATH="$JAVA_HOME/bin:$TYPEFLUX_TOOLS/flutter-typeflux/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

mkdir -p "$GRADLE_USER_HOME" "$PUB_CACHE" "$ANDROID_USER_HOME"
cd "$TYPEFLUX_WORKSPACE/codes/typeflux/typeflux-flutter"
```

Ensure `$GRADLE_USER_HOME/gradle.properties` contains these settings, preserving
any other settings already present:

```properties
org.gradle.vfs.watch=false
kotlin.compiler.execution.strategy=in-process
```

These are local Gradle user settings, not a repository-wide change. The second
setting runs the Kotlin compiler in the Gradle process, as described in the
[official Kotlin compiler execution strategy documentation](https://kotlinlang.org/docs/compiler-execution-strategy.html).

The local, uncommitted `android/local.properties` used for this build points
`sdk.dir` to the writable SDK and `flutter.sdk` to `.tools/flutter-typeflux`.
Keep those paths consistent with the environment above. The exact Android user
home used by the build is `typeflux-android-userhome`; the separate
`typeflux-android-user-home` directory was used only during initial NDK setup.

Build the ARM64 debug APK:

```sh
flutter build apk --debug --target-platform android-arm64
```

The first build can download Gradle, Android, Kotlin and AndroidX dependencies.
The SDK links above depend on the original SDK remaining installed. This is a
local development setup, not a self-contained SDK archive or a release signing
configuration.

## Observed progress and limits

An earlier attempt using the existing JDK 26 did not finish Flutter's
`:gradle:compileKotlin` task. The current attempt uses the isolated JDK 21 and
the two local Gradle settings shown above. It passed Flutter's Kotlin plugin
compilation, entered Android plugin configuration, installed the additional
platform 35, and proceeded to AndroidX dependency downloads.

This is an observed change in build progress. Several environment settings
changed between attempts, so it does not establish the complete cause of the
earlier stall or prove that either setting alone resolved it.

The ARM64 debug APK build subsequently passed. A smaller profile test package
was also built with `flutter build apk --profile --target-platform android-arm64`.
Both APK signatures and ZIP integrity were verified. It has not been installed on a device. Consult
[validation.md](validation.md) for package details and the device, keyboard,
plugin and backend checks that still need separate evidence.

## Final v4 ARM64 delivery build

After setting the environment above, build a single-ABI profile test package:

```sh
flutter build apk --profile --target-platform android-arm64 --split-per-abi \
  --android-project-arg=force-version-code-ignoring-abi=true
```

The output is `build/app/outputs/flutter-apk/app-arm64-v8a-profile.apk`.
The split option excludes plugin libraries for other ABIs. The project argument
keeps version code 1; it is supported by the locked Flutter toolchain. The current
package's signature, contents and metadata were checked; see `validation.md` for
the size and SHA-256. It has not been installed on a device.
