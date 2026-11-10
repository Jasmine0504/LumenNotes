from PIL import Image, ImageDraw, ImageFilter, ImageFont
import os

root = r"D:\DSH专用文件夹\LumenNotes"
icon_dir = os.path.join(root, "Resources", "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(icon_dir, exist_ok=True)
size = 1024
img = Image.new("RGB", (size, size), (9, 13, 28))
px = img.load()
for y in range(size):
    for x in range(size):
        t = (x / size * 0.55 + y / size * 0.45)
        px[x, y] = (int(13 + 45 * t), int(19 + 44 * t), int(44 + 150 * t))

glow = Image.new("RGB", (size, size), (0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse((540, -180, 1180, 420), fill=(64, 120, 255))
gd.ellipse((-260, 560, 420, 1240), fill=(155, 92, 255))
gd.ellipse((600, 650, 1120, 1180), fill=(0, 196, 220))
glow = glow.filter(ImageFilter.GaussianBlur(180))
img = Image.blend(img, glow, 0.45)
d = ImageDraw.Draw(img, "RGBA")
d.rounded_rectangle((172, 196, 560, 868), radius=118, fill=(255, 255, 255, 34),
                    outline=(255, 255, 255, 150), width=5)
d.rounded_rectangle((196, 220, 536, 552), radius=92, outline=(255, 255, 255, 55), width=2)
font = ImageFont.truetype(r"C:\Windows\Fonts\georgiab.ttf", 430)
d.text((354, 246), "Aa", font=font, fill=(255, 255, 255, 245), anchor="mm")
for i, (w, alpha) in enumerate([(260, 150), (210, 110), (160, 80)]):
    y = 650 + i * 58
    d.rounded_rectangle((262, y, 262 + w, y + 18), radius=9, fill=(255, 255, 255, alpha))
d.ellipse((452, 790, 520, 858), fill=(255, 196, 84, 255))
img.save(os.path.join(icon_dir, "AppIcon-1024.png"), "PNG")

files = {
    os.path.join(root, "Resources", "Assets.xcassets", "Contents.json"): '{\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n',
    os.path.join(icon_dir, "Contents.json"): '{\n  "images" : [\n    {\n      "filename" : "AppIcon-1024.png",\n      "idiom" : "universal",\n      "platform" : "ios",\n      "size" : "1024x1024"\n    }\n  ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n',
    os.path.join(root, "Resources", "Assets.xcassets", "AccentColor.colorset", "Contents.json"): '{\n  "colors" : [\n    {\n      "color" : {\n        "color-space" : "srgb",\n        "components" : { "alpha" : "1.000", "blue" : "0.980", "green" : "0.420", "red" : "0.290" }\n      },\n      "idiom" : "universal"\n    }\n  ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n',
    os.path.join(root, "Resources", "Assets.xcassets", "LaunchBackground.colorset", "Contents.json"): '{\n  "colors" : [\n    {\n      "color" : {\n        "color-space" : "srgb",\n        "components" : { "alpha" : "1.000", "blue" : "0.110", "green" : "0.075", "red" : "0.050" }\n      },\n      "idiom" : "universal"\n    }\n  ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n',
}
for path, text in files.items():
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
print("icon and assets written")
