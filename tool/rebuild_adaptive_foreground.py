from PIL import Image
import os

root = r"C:\Users\User\Documents\flutter\new_gmserp"
logo_path = os.path.join(root, "assets", "branding", "gmserp_logo.png")
logo = Image.open(logo_path).convert("RGBA")

# Full-canvas logo; padding comes from adaptive_icon_foreground_inset (18%).
size = 1024
fg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
scaled = logo.resize((size, size), Image.Resampling.LANCZOS)
fg.paste(scaled, (0, 0), scaled)

fg_path = os.path.join(root, "assets", "branding", "gmserp_logo_foreground.png")
fg.save(fg_path, "PNG")
print("saved foreground", fg_path)
