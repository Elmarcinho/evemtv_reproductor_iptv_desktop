#!/usr/bin/env python3
"""Genera los íconos de la app a partir de assets/branding/logo_source.png.

- Ícono (Windows .ico, macOS AppIcon, Linux): solo el símbolo sobre un
  cuadrado redondeado oscuro. El texto "EVEMTV" no se lee a 16-48 px y el
  blanco desaparece sobre fondos claros.
- Logo para la interfaz: el logo completo recortado (texto blanco pensado
  para el tema oscuro de la app).

Uso: python3 tool/generate_icons.py   (requiere Pillow)
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets/branding/logo_source.png"
BACKGROUND = (13, 17, 23, 255)  # AppColors.background (#0D1117)
ALPHA_CUT = 20


def bbox(img: Image.Image) -> tuple[int, int, int, int]:
    mask = img.getchannel("A").point(lambda v: 255 if v > ALPHA_CUT else 0)
    return mask.getbbox()


def symbol(src: Image.Image) -> Image.Image:
    """El símbolo es la parte superior, separada del texto por una franja
    transparente."""
    full = bbox(src)
    alpha = src.getchannel("A")
    # Primera fila vacía debajo del inicio del símbolo = fin del símbolo.
    top = full[1]
    y = top
    while y < full[3]:
        row = alpha.crop((0, y, src.width, y + 1))
        if row.getextrema()[1] <= ALPHA_CUT and y - top > 50:
            break
        y += 1
    part = src.crop((0, top, src.width, y))
    return part.crop(bbox(part))


def rounded_square(size: int, radius: float, inset: int = 0) -> Image.Image:
    """Cuadrado redondeado con antialias (dibujado a 4x y reducido)."""
    scale = 4
    big = Image.new("RGBA", (size * scale, size * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(big)
    draw.rounded_rectangle(
        (inset * scale, inset * scale, (size - inset) * scale - 1, (size - inset) * scale - 1),
        radius=radius * scale,
        fill=BACKGROUND,
    )
    return big.resize((size, size), Image.LANCZOS)


def icon(mark: Image.Image, size: int, *, inset: int, radius_ratio: float, mark_ratio: float) -> Image.Image:
    canvas = rounded_square(size, (size - 2 * inset) * radius_ratio, inset)
    inner = size - 2 * inset
    target_w = int(inner * mark_ratio)
    scale = target_w / mark.width
    m = mark.resize((target_w, max(1, int(mark.height * scale))), Image.LANCZOS)
    canvas.alpha_composite(m, ((size - m.width) // 2, (size - m.height) // 2))
    return canvas


def main() -> None:
    src = Image.open(SOURCE).convert("RGBA")
    mark = symbol(src)

    branding = ROOT / "assets/branding"
    # Logo completo para la interfaz.
    logo = src.crop(bbox(src))
    logo.thumbnail((720, 720), Image.LANCZOS)
    logo.save(branding / "logo.png", optimize=True)
    # Símbolo suelto (encabezados compactos) y ventana de Linux.
    mark_small = mark.copy()
    mark_small.thumbnail((256, 256), Image.LANCZOS)
    mark_small.save(branding / "mark.png", optimize=True)

    # Windows / Linux: cuadrado casi a sangre.
    base = icon(mark, 1024, inset=24, radius_ratio=0.22, mark_ratio=0.72)
    base.resize((256, 256), Image.LANCZOS).save(branding / "icon_256.png", optimize=True)
    base.save(branding / "icon_1024.png", optimize=True)
    ico_sizes = [16, 24, 32, 48, 64, 128, 256]
    base.save(
        ROOT / "windows/runner/resources/app_icon.ico",
        sizes=[(s, s) for s in ico_sizes],
    )

    # macOS: cuadrado de 824 px dentro de 1024 (grilla estándar de íconos).
    mac = icon(mark, 1024, inset=100, radius_ratio=0.225, mark_ratio=0.70)
    appicon = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for s in [16, 32, 64, 128, 256, 512, 1024]:
        mac.resize((s, s), Image.LANCZOS).save(appicon / f"app_icon_{s}.png", optimize=True)

    print("Íconos generados.")


if __name__ == "__main__":
    main()
