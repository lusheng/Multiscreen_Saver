#!/usr/bin/env python3
"""MIT synthetic orientation albums; uses Pillow only for development fixtures."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
root = Path(__file__).resolve().parent.parent / 'LocalPhotos' / 'Playback'
font = ImageFont.load_default(size=150)
for route, base in [('H', (20, 85, 180)), ('V', (200, 90, 15))]:
    folder = root / route; folder.mkdir(parents=True, exist_ok=True)
    for number, (size, ext) in enumerate([((1920,1080),'jpg'), ((1080,1920),'png'), ((1600,1600),'webp'), ((3000,600),'jpeg'), ((600,3000),'png')], 1):
        im = Image.new('RGB', size, base); d = ImageDraw.Draw(im)
        for x in range(0, size[0], 100): d.line((x,0,x,size[1]),fill=(100,140,180),width=3)
        for y in range(0, size[1], 100): d.line((0,y,size[0],y),fill=(100,140,180),width=3)
        d.rectangle((0,0,size[0]-1,size[1]-1),outline='white',width=20)
        label=f'{route} {number}'
        d.text((size[0]/2,size[1]/2),label,font=font,anchor='mm',fill='white',stroke_width=2)
        im.save(folder / f'{number:02d}-{route}.{ext}')
    alpha=Image.new('RGBA',(1000,1000),(0,0,0,0));d=ImageDraw.Draw(alpha)
    d.ellipse((50,50,950,950),fill=(*base,180));d.text((500,500),f'{route} alpha',font=font,anchor='mm',fill='white')
    alpha.save(folder / f'06-{route}-alpha.png')
    alpha.save(folder / f'07-{route}-alpha.webp',lossless=True)
print('Generated H/V synthetic playback albums in LocalPhotos/Playback')
