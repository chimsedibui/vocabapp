#!/usr/bin/env python3
"""Place icons rendered by app/test/tool/brand_icons_test.dart.

Usage: python3 -I scripts/pack-icons.py <BRAND_OUT folder>
Writes the Windows .ico (PNG entries, Vista+) and the Android launcher
mipmaps plus the adaptive icon (teal background, card foreground).
"""
import pathlib
import shutil
import struct
import sys

src = pathlib.Path(sys.argv[1])
app = pathlib.Path(__file__).resolve().parent.parent / "app"

sizes = [16, 20, 24, 32, 40, 48, 64, 256]
images = [(src / f"mark-{s}.png").read_bytes() for s in sizes]
header = struct.pack("<HHH", 0, 1, len(images))
offset = 6 + 16 * len(images)
entries = b""
for size, data in zip(sizes, images):
    dim = 0 if size == 256 else size
    entries += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(data), offset)
    offset += len(data)
(app / "windows/runner/resources/app_icon.ico").write_bytes(header + entries + b"".join(images))

res = app / "android/app/src/main/res"
for density, legacy, foreground in [
    ("mdpi", 48, 108),
    ("hdpi", 72, 162),
    ("xhdpi", 96, 216),
    ("xxhdpi", 144, 324),
    ("xxxhdpi", 192, 432),
]:
    folder = res / f"mipmap-{density}"
    shutil.copy(src / f"mark-{legacy}.png", folder / "ic_launcher.png")
    shutil.copy(src / f"foreground-{foreground}.png", folder / "ic_launcher_foreground.png")

(res / "mipmap-anydpi-v26").mkdir(exist_ok=True)
(res / "mipmap-anydpi-v26/ic_launcher.xml").write_text(
    """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
"""
)
(res / "values/ic_launcher_background.xml").write_text(
    """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#0B7469</color>
</resources>
"""
)
print("icons written")
