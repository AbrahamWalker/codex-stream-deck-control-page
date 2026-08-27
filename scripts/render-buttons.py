import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "buttons"

PALETTES = {
    "navigation": (24, 53, 83, 87, 177, 255),
    "create": (16, 71, 86, 45, 212, 191),
    "voice": (18, 82, 61, 74, 225, 144),
    "prompt": (63, 44, 102, 170, 112, 255),
    "annotate": (104, 34, 65, 255, 91, 151),
    "panel": (35, 65, 103, 75, 166, 255),
    "files": (77, 58, 21, 255, 190, 74),
    "chat": (69, 44, 96, 204, 126, 255),
    "copy": (54, 50, 105, 124, 132, 255),
    "system": (54, 61, 70, 174, 184, 197),
}


def font(name, size):
    paths = {
        "bold": Path("C:/Windows/Fonts/seguisb.ttf"),
        "regular": Path("C:/Windows/Fonts/segoeui.ttf"),
    }
    return ImageFont.truetype(str(paths[name]), size=size)


def fit_font(draw, lines, max_width, start=28, minimum=17):
    for size in range(start, minimum - 1, -1):
        candidate = font("bold", size)
        if all(draw.textbbox((0, 0), line, font=candidate)[2] <= max_width for line in lines):
            return candidate
    return font("bold", minimum)


def render(item):
    size = 144
    dark_r, dark_g, dark_b, bright_r, bright_g, bright_b = PALETTES[item["category"]]
    image = Image.new("RGB", (size, size), (10, 13, 17))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((5, 5, 138, 138), radius=22, fill=(dark_r, dark_g, dark_b), outline=(bright_r, bright_g, bright_b), width=5)
    draw.rounded_rectangle((12, 12, 132, 31), radius=8, fill=(bright_r, bright_g, bright_b))
    category = item["category"].upper()
    category_font = font("bold", 12)
    category_box = draw.textbbox((0, 0), category, font=category_font)
    draw.text(((size - (category_box[2] - category_box[0])) / 2, 14), category, font=category_font, fill=(7, 13, 18))

    lines = item["label"].split("\n")
    label_font = fit_font(draw, lines, 122)
    heights = [draw.textbbox((0, 0), line, font=label_font)[3] for line in lines]
    total_height = sum(heights) + (3 * (len(lines) - 1))
    y = 45 + max(0, (53 - total_height) / 2)
    for line, line_height in zip(lines, heights):
        box = draw.textbbox((0, 0), line, font=label_font)
        draw.text(((size - (box[2] - box[0])) / 2, y), line, font=label_font, fill="white")
        y += line_height + 3

    shortcut = item["shortcut"]
    shortcut_font = font("bold", 12 if len(shortcut) <= 13 else 10)
    shortcut_box = draw.textbbox((0, 0), shortcut, font=shortcut_font)
    shortcut_width = shortcut_box[2] - shortcut_box[0]
    draw.rounded_rectangle((12, 113, 132, 134), radius=8, fill=(8, 12, 17))
    draw.text(((size - shortcut_width) / 2, 116), shortcut, font=shortcut_font, fill=(bright_r, bright_g, bright_b))
    return image


OUTPUT.mkdir(parents=True, exist_ok=True)
layout = json.loads((ROOT / "layout.json").read_text(encoding="utf-8"))
for item in layout:
    filename = item["position"].replace(",", "-") + ".png"
    render(item).save(OUTPUT / filename, optimize=True)

preview = Image.new("RGB", (8 * 156 + 24, 4 * 156 + 24), (35, 38, 43))
for item in layout:
    column, row = (int(value) for value in item["position"].split(","))
    button = Image.open(OUTPUT / (item["position"].replace(",", "-") + ".png"))
    preview.paste(button, (12 + column * 156, 12 + row * 156))
preview.save(ROOT / "codex-page-preview.png", optimize=True)

print(f"Rendered {len(layout)} labeled Stream Deck buttons to {OUTPUT}")
