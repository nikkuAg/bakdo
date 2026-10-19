# Inscribo icon

`app-icon.svg` is the source of the app icon: a golden quill on a starry midnight sky, its nib writing a
sparkling sound wave that settles into a line of text. The app shows this artwork in its sidebar and welcome
screen; the menu bar uses the `wand.and.stars` symbol (`BrandMark` in `Sources/Inscribo/UI/Theme.swift`).

Regenerate `AppIcon.icns` after editing the SVG:

```bash
cd design && mkdir -p AppIcon.iconset
for s in 16 32 64 128 256 512 1024; do qlmanage -t -s $s -o . app-icon.svg >/dev/null && mv app-icon.svg.png px$s.png; done
cp px16.png AppIcon.iconset/icon_16x16.png;     cp px32.png AppIcon.iconset/icon_16x16@2x.png
cp px32.png AppIcon.iconset/icon_32x32.png;     cp px64.png AppIcon.iconset/icon_32x32@2x.png
cp px128.png AppIcon.iconset/icon_128x128.png;  cp px256.png AppIcon.iconset/icon_128x128@2x.png
cp px256.png AppIcon.iconset/icon_256x256.png;  cp px512.png AppIcon.iconset/icon_256x256@2x.png
cp px512.png AppIcon.iconset/icon_512x512.png;  cp px1024.png AppIcon.iconset/icon_512x512@2x.png
iconutil -c icns AppIcon.iconset -o AppIcon.icns && rm -rf AppIcon.iconset px*.png
```

`archive/` holds earlier icon concepts from when the app was called Bakdo.
