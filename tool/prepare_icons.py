from PIL import Image
import os

src = r"C:\Users\User\.cursor\projects\c-Users-User-Documents-flutter-new-gmserp\assets\c__Users_User_AppData_Roaming_Cursor_User_workspaceStorage_fd4eb7a278f583075361bec15e16e083_images_gms_logo-d6d6a713-d7d3-425f-acc3-80001dc47c31.png"
out_dir = r"C:\Users\User\Documents\flutter\new_gmserp\assets\branding"
os.makedirs(out_dir, exist_ok=True)

img = Image.open(src).convert("RGBA")
w, h = img.size
px = img.load()
cx, cy = w / 2.0, h / 2.0

radii = []
for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        if g > 160 and r > 80 and b < 120 and (r + g + b) > 280:
            dx, dy = x - cx, y - cy
            radii.append((dx * dx + dy * dy) ** 0.5)

radius = sorted(radii)[int(len(radii) * 0.98)] if radii else min(w, h) * 0.48
radius = radius + max(2, w * 0.01)
print("size", w, h, "radius", radius)

out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
opx = out.load()
for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        dx, dy = x - cx, y - cy
        dist = (dx * dx + dy * dy) ** 0.5
        if dist > radius + 1.5:
            continue
        if dist > radius:
            alpha = int(255 * (1 - (dist - radius) / 1.5))
        else:
            alpha = 255
        opx[x, y] = (r, g, b, alpha)

bbox = out.getbbox()
pad = int(max(w, h) * 0.02)
bbox = (
    max(0, bbox[0] - pad),
    max(0, bbox[1] - pad),
    min(w, bbox[2] + pad),
    min(h, bbox[3] + pad),
)
cropped = out.crop(bbox)

side = max(cropped.size)
canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
ox = (side - cropped.size[0]) // 2
oy = (side - cropped.size[1]) // 2
canvas.paste(cropped, (ox, oy), cropped)

master = canvas.resize((1024, 1024), Image.Resampling.LANCZOS)
logo_path = os.path.join(out_dir, "gmserp_logo.png")
master.save(logo_path, "PNG")
print("saved", logo_path, master.size)

fg = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
logo_scaled = master.resize((800, 800), Image.Resampling.LANCZOS)
fg.paste(logo_scaled, ((1024 - 800) // 2, (1024 - 800) // 2), logo_scaled)
fg_path = os.path.join(out_dir, "gmserp_logo_foreground.png")
fg.save(fg_path, "PNG")
print("saved", fg_path)

notif = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
src_px = master.load()
dst_px = notif.load()
for y in range(1024):
    for x in range(1024):
        r, g, b, a = src_px[x, y]
        if a < 16:
            continue
        dst_px[x, y] = (255, 255, 255, a)

notif_path = os.path.join(out_dir, "gmserp_notification_icon.png")
notif.save(notif_path, "PNG")
print("saved", notif_path)
print("corner", master.getpixel((10, 10)))
