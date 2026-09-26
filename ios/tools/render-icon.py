"""Render the code-native NeonWave waveform icon; no external raster artwork."""
from pathlib import Path
from PIL import Image, ImageDraw
import math

root = Path(__file__).resolve().parents[1]
size = 1024
image = Image.new('RGB', (size, size))
pixels = image.load()
for y in range(size):
    for x in range(size):
        glow = max(0, 1 - math.hypot(x - 310, y - 180) / 1050)
        pixels[x, y] = (int(24 + 48 * glow), int(37 + 64 * glow), int(97 + 139 * glow))
draw = ImageDraw.Draw(image)
for radius in (305, 398, 486):
    draw.ellipse((512-radius, 512-radius, 512+radius, 512+radius), outline=(81, 111, 221), width=2)
for x, height in zip((290, 386, 482, 578, 674), (160, 310, 444, 248, 366)):
    draw.rounded_rectangle((x, 512-height//2, x+60, 512+height//2), radius=30, fill=(247, 249, 255))
destination = root / 'NeonWave/Assets.xcassets/AppIcon.appiconset/AppIcon.png'
image.save(destination)
print(destination)
