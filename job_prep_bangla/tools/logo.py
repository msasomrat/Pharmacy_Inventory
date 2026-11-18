#!/usr/bin/env python3
"""নিয়োগ দরবার logo built from the রসায়ন দরবার logo's own letterforms.

The whole word দরবার is cut straight from the রসায়ন দরবার logo (white PNG);
ি, ে and গ, which that logo does not contain, are drawn to its measured metrics:
matra 45 px thick, stems 53 px, x-height 262 px, 22 px letter gaps.
usage: logo.py SOURCE_LOGO_WHITE.png OUT_DIR   ->  writes OUT_DIR/logo_parts + logo html
"""
import json, sys
from pathlib import Path
from PIL import Image

SRC, OUT = Path(sys.argv[1]), Path(sys.argv[2]).resolve()
P = OUT / "logo_parts"; P.mkdir(parents=True, exist_ok=True)
im = Image.open(SRC).convert("RGBA")
crops = {  # (x0, y0, x1, y1) in the 1536 px source; matra top of the upper row is y=505
    "na":  (1021, 505, 1189, 800),
    "ya":  (835, 505, 995, 800),
    "aa":  (755, 505, 809, 800),
    "dorbar": (521, 800, 1196, 1050),
}
for k, b in crops.items():
    im.crop(b).save(P / f"{k}.png")

M, X, STEM, GAP = 45, 262, 53, 22   # matra, x-height, stem width, letter gap
def wpx(k): b = crops[k]; return b[2] - b[0]

# upper row layout (x of each glyph's left edge, relative to row start)
row, x = [], 0
def put(kind, w):
    global x
    row.append((kind, x)); x += w + GAP
put("i", STEM); put("na", wpx("na")); put("e", 105); put("ya", wpx("ya")); x += 5; put("aa", wpx("aa")); x += 4; put("ga", 166)
row_w = x - GAP
# the hand-drawn ি/ে/গ were hard to read, so the upper word is set in a real font instead
import shutil
NY = json.loads((Path(__file__).parent / "niyog_anek.json").read_text())
shutil.copy(Path(__file__).parent / "niyog_anek.png", P / "niyog.png")
row_w = NY["w"]

def glyph_svg(kind):
    W = "#fff"
    if kind == "i":   # ি: stem + hook over the next letter
        return (f"<rect x='0' y='0' width='{STEM}' height='{X}' fill='{W}'/>"
                f"<path d='M26.5 24 V-38 Q26.5 -76 64 -76 H150 Q183 -76 183 -43 V12' stroke='{W}' stroke-width='44' fill='none'/>")
    if kind == "e":   # ে: matra piece + hanging stroke curling up at the foot
        return (f"<rect x='0' y='0' width='105' height='{M}' fill='{W}'/>"
                f"<path d='M23 30 V168 Q23 212 64 212 Q88 212 88 160' stroke='{W}' stroke-width='46' fill='none'/>")
    if kind == "ga":  # গ: matra + right stem + left hook
        return (f"<rect x='0' y='0' width='166' height='{M}' fill='{W}'/>"
                f"<rect x='{166-STEM}' y='0' width='{STEM}' height='{X}' fill='{W}'/>"
                f"<path d='M23 30 V182 Q23 226 62 226 Q84 226 84 168' stroke='{W}' stroke-width='46' fill='none'/>")

def logo_html(color="#fff", frame="#fff", bg="transparent", word2=None, scale=1.0, pad=(0, 0)):
    """Return (html, w, h). Coordinates follow the source logo; whole thing is scaled."""
    L0, T0 = 150, 260                       # canvas position of row-1 matra top-left
    r2x = L0 + row_w + 7 - wpx("dorbar")    # দরবার right-aligned like the source (+7)
    r2y = T0 + 295
    W, H = int((L0 + row_w + 210) ), int(r2y + 250 + 200)
    parts = []
    # নিয়োগ: Anek Bangla ExtraBold 75% width, rendered at the source x-height (262 px)
    parts.append(f"<image href='logo_parts/niyog.png' x='{L0}' y='{T0 - NY['matra_top']}' width='{NY['w']}' height='{NY['h']}'/>")
    parts.append(f"<image href='logo_parts/dorbar.png' x='{r2x}' y='{r2y}' width='{wpx('dorbar')}' height='250'/>")
    # hexagon corner frame, same geometry as the source (double line on the diagonals)
    Lx, Ty = L0 - 84, T0 - 250
    Rx, By = L0 + row_w + 7 + 56, r2y + 249 + 164
    fs = f"stroke='{frame}' stroke-width='12' fill='none' stroke-linejoin='miter'"
    parts.append(f"<polyline points='{Lx},{Ty+470} {Lx},{Ty+135} {Lx+225},{Ty} {Lx+455},{Ty+133}' {fs}/>")
    parts.append(f"<polyline points='{Lx+32},{Ty+150} {Lx+223},{Ty+36}' {fs}/>")
    parts.append(f"<polyline points='{Rx},{By-395} {Rx},{By-135} {Rx-225},{By} {Rx-455},{By-133}' {fs}/>")
    parts.append(f"<polyline points='{Rx-32},{By-150} {Rx-223},{By-36}' {fs}/>")
    frame_parts = [q for q in parts if q.startswith("<polyline")]
    inner = "".join(q for q in parts if not q.startswith("<polyline"))
    # colorize: white source parts -> chosen color via SVG filter
    filt = (f"<filter id='tint'><feFlood flood-color='{color}'/><feComposite in2='SourceAlpha' operator='in'/></filter>")
    bx0, by0, bx1, by1 = Lx - 10, Ty - 10, Rx + 10, By + 10
    vw, vh = bx1 - bx0, by1 - by0
    svg = (f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='{bx0} {by0} {vw} {vh}' width='{vw*scale:.0f}' height='{vh*scale:.0f}'>"
           f"<defs>{filt}</defs><g filter='url(#tint)'>{inner}</g>{''.join(frame_parts)}</svg>")
    return svg, vw, vh

if __name__ == "__main__":
    svg, vw, vh = logo_html()
    (OUT / "logo_bbox.json").write_text(json.dumps({"w": vw, "h": vh}))
    print("row width", row_w, "logo box", vw, vh)
