# Issue para media-kit/media-kit (para publicar)

**Title:** [macOS] App crashes when opening a video if no hardware-accelerated OpenGL renderer is available (`OpenGLHelpers.swift:25`, force unwrap)

**Body:**

### Description

On macOS, `media_kit_video` crashes the whole app when a `VideoController`
is created and a video is opened on a machine that has no
hardware-accelerated OpenGL renderer (for example, GitHub Actions macOS
runners / other virtual machines). There is no error that the app can
handle: the process terminates.

### Cause

`media_kit_video/macos/Classes/plugin/gl/OpenGLHelpers.swift`,
`createPixelFormat()` (media_kit_video 2.0.1):

```swift
let attributes: [CGLPixelFormatAttribute] = [
  kCGLPFAOpenGLProfile,
  CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
  kCGLPFAAccelerated,
  // ...
]
var npix: GLint = 0
var pixelFormat: CGLPixelFormatObj?
CGLChoosePixelFormat(attributes, &pixelFormat, &npix)

return pixelFormat!   // line 25
```

When no renderer satisfies `kCGLPFAAccelerated`, `CGLChoosePixelFormat`
leaves `pixelFormat` as `nil` and the force unwrap aborts the process.

System log from the crash (macOS runner, `macos-latest`):

```
EvemTv[20644:11172] (libswiftCore.dylib) media_kit_video/OpenGLHelpers.swift:25: Fatal error: Unexpectedly found nil while unwrapping an Optional value
```

`createContext()` has a similar pattern (`exit(1)` on
`CGLCreateContext` failure).

### Steps to reproduce

1. Run any app that creates a `Player` + `VideoController` and shows a
   `Video` widget on a macOS VM without hardware OpenGL (e.g. a GitHub
   Actions `macos-latest` runner, `flutter test integration_test -d macos`).
2. Open any video.
3. The app terminates with the fatal error above.

A `Player` without `VideoController` works fine on the same machine.

### Suggested fix

- Check the return code of `CGLChoosePixelFormat` and whether
  `pixelFormat` is `nil`.
- If it fails, retry **without `kCGLPFAAccelerated`** (and without the
  attributes that require it), so a software renderer can be used.
- If that also fails, report an error through the `VideoController` /
  `Player` error stream instead of crashing (same for `createContext()`:
  avoid `exit(1)`).

### Environment

- media_kit 1.2.6, media_kit_video 2.0.1, media_kit_libs_video 1.0.7
- Flutter 3.47.5 (stable)
- macOS runner `macos-latest` (GitHub Actions)
