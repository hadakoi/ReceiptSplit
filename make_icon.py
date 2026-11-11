"""Draw the app's geometric receipt icon; requires Pillow."""
from pathlib import Path
import json
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parent / "ReceiptSplit" / "Assets.xcassets"
icons = root / "AppIcon.appiconset"
icons.mkdir(parents=True, exist_ok=True)
image = Image.new("RGB", (1024, 1024), "#087F7B")
draw = ImageDraw.Draw(image)
draw.rounded_rectangle((266, 154, 758, 866), radius=48, fill="#F5F7F0")
for x in range(266, 758, 82):
    draw.polygon([(x, 866), (x + 41, 825), (x + 82, 866)], fill="#087F7B")
for y, width in [(294, 286), (388, 212), (482, 286)]:
    draw.rounded_rectangle((366, y, 366 + width, y + 26), radius=13, fill="#087F7B")
draw.line([(366, 628), (628, 628)], fill="#087F7B", width=28)
draw.line([(573, 581), (628, 628), (573, 675)], fill="#087F7B", width=28, joint="curve")
draw.line([(392, 727), (628, 727)], fill="#087F7B", width=28)
draw.line([(447, 680), (392, 727), (447, 774)], fill="#087F7B", width=28, joint="curve")
image.save(icons / "AppIcon.png")
(root / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
(icons / "Contents.json").write_text(json.dumps({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}, indent=2))
