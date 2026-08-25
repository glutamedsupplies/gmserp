from PIL import Image
import os

root = r"C:\Users\User\Documents\flutter\new_gmserp"
logo = Image.open(os.path.join(root, "assets", "branding", "gmserp_logo.png")).convert("RGBA")
w, h = logo.size
src = logo.load()

# White disc with GMS letter cutouts (Android status-bar friendly)
notif = Image.new("RGBA", (w, h), (0, 0, 0, 0))
dst = notif.load()
for y in range(h):
    for x in range(w):
        r, g, b, a = src[x, y]
        if a < 16:
            continue
        luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        # Black letter forms become transparent cutouts
        if luminance < 55 and g < 80:
            continue
        # Lime / border remain as white silhouette
        dst[x, y] = (255, 255, 255, a)

notif_path = os.path.join(root, "assets", "branding", "gmserp_notification_icon.png")
notif.save(notif_path, "PNG")
print("saved", notif_path)

sizes = {
    "drawable-mdpi": 24,
    "drawable-hdpi": 36,
    "drawable-xhdpi": 48,
    "drawable-xxhdpi": 72,
    "drawable-xxxhdpi": 96,
}
res = os.path.join(root, "android", "app", "src", "main", "res")
for folder, size in sizes.items():
    out_dir = os.path.join(res, folder)
    os.makedirs(out_dir, exist_ok=True)
    scaled = notif.resize((size, size), Image.Resampling.LANCZOS)
    path = os.path.join(out_dir, "ic_stat_gmserp.png")
    scaled.save(path, "PNG")
    print("saved", path)

# Color large icon already fine; refresh from transparent logo
large_dir = os.path.join(res, "drawable")
os.makedirs(large_dir, exist_ok=True)
logo.resize((192, 192), Image.Resampling.LANCZOS).save(
    os.path.join(large_dir, "ic_notification_gmserp.png"), "PNG"
)
print("refreshed large color notification icon")
