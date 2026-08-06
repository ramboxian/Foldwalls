import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


LIBRARY_ROOT = Path('/Users/bytedance/Library/Application Support/Foldwalls')
MANIFEST_PATH = LIBRARY_ROOT / 'library.json'
OUTPUT_DIR = Path('/tmp/foldwalls-review')
CELL_WIDTH = 640
IMAGE_HEIGHT = 360
LABEL_HEIGHT = 76
COLS = 3
ROWS = 4


def load_font(size: int):
    candidates = [
        '/System/Library/Fonts/PingFang.ttc',
        '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
        '/System/Library/Fonts/Helvetica.ttc',
    ]
    for candidate in candidates:
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default()


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    records = json.loads(MANIFEST_PATH.read_text(encoding='utf-8'))
    title_font = load_font(24)
    detail_font = load_font(17)
    index = []

    for sheet_start in range(0, len(records), COLS * ROWS):
        canvas = Image.new('RGB', (COLS * CELL_WIDTH, ROWS * (IMAGE_HEIGHT + LABEL_HEIGHT)), '#101218')
        draw = ImageDraw.Draw(canvas)
        for offset, item in enumerate(records[sheet_start:sheet_start + COLS * ROWS]):
            position = sheet_start + offset + 1
            col = offset % COLS
            row = offset // COLS
            x = col * CELL_WIDTH
            y = row * (IMAGE_HEIGHT + LABEL_HEIGHT)
            thumbnail_path = Path(item['thumbnailPath'])
            with Image.open(thumbnail_path) as source:
                image = ImageOps.fit(source.convert('RGB'), (CELL_WIDTH, IMAGE_HEIGHT), method=Image.Resampling.LANCZOS)
            canvas.paste(image, (x, y))
            draw.rectangle((x, y + IMAGE_HEIGHT, x + CELL_WIDTH, y + IMAGE_HEIGHT + LABEL_HEIGHT), fill='#171A22')
            draw.text((x + 14, y + IMAGE_HEIGHT + 9), f'{position:02d}  {item.get("title", "")}', font=title_font, fill='#FFFFFF')
            detail = f'{item.get("kind", "")}  {item.get("width", "")}×{item.get("height", "")}  {item.get("duration", 0):.1f}s'
            draw.text((x + 14, y + IMAGE_HEIGHT + 43), detail, font=detail_font, fill='#A8AEBB')
            index.append({
                'number': position,
                'id': item['id'],
                'currentTitle': item.get('title', ''),
                'kind': item.get('kind', ''),
                'mediaPath': item['localPath'],
                'thumbnailPath': item['thumbnailPath'],
                'width': item.get('width'),
                'height': item.get('height'),
                'duration': item.get('duration'),
                'palette': item.get('palette', {}),
            })
        sheet_number = sheet_start // (COLS * ROWS) + 1
        canvas.save(OUTPUT_DIR / f'contact-sheet-{sheet_number}.jpg', quality=91)

    (OUTPUT_DIR / 'index.json').write_text(json.dumps(index, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Created {len(index)} review entries in {OUTPUT_DIR}')


if __name__ == '__main__':
    main()
