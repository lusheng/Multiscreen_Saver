#!/usr/bin/env python3
"""Original synthetic format/EXIF fixtures (MIT); Pillow is a test-only dependency."""
from pathlib import Path
from PIL import Image, ImageDraw, features
assert features.check('webp'), 'Pillow WebP encoding is required for this fixture set'
root = Path(__file__).resolve().parent.parent / 'LocalPhotos' / 'Formats'
root.mkdir(parents=True, exist_ok=True)
im = Image.new('RGB', (400, 200))
d = ImageDraw.Draw(im)
for rect, color in [((0, 0, 199, 99), (255, 0, 0)), ((200, 0, 399, 99), (0, 255, 0)),
                    ((0, 100, 199, 199), (255, 255, 0)), ((200, 100, 399, 199), (0, 0, 255))]:
    d.rectangle(rect, fill=color)
for ext in ['jpg', 'jpeg', 'png', 'webp']:
    im.save(root / f'quadrants.{ext}')
for orientation in range(1, 9):
    exif = Image.Exif(); exif[274] = orientation
    im.save(root / f'orientation-{orientation}.jpg', exif=exif, quality=95)
alpha = Image.new('RGBA', (200, 400), (0, 0, 0, 0))
ImageDraw.Draw(alpha).rectangle((50, 100, 150, 300), fill=(255, 0, 0, 180))
alpha.save(root / 'transparent.png')
alpha.save(root / 'transparent.webp', lossless=True)
(root / 'broken.jpg').write_text('not an image')
print('Generated original synthetic format fixtures in LocalPhotos/Formats')
