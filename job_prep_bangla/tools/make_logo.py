#!/usr/bin/env python3
"""Render logo variants + Facebook profile/cover. usage: make_logo.py SOURCE_LOGO_WHITE.png OUT_DIR"""
import json, sys, subprocess
from pathlib import Path
sys.argv = [sys.argv[0], sys.argv[1], sys.argv[2]]
T = Path(__file__).parent
import importlib.util
spec = importlib.util.spec_from_file_location("logo", T / "logo.py"); L = importlib.util.module_from_spec(spec); spec.loader.exec_module(L)
OUT = Path(sys.argv[2]).resolve()
FONTS = (T / "fonts" / "local.css").read_text().replace("url(", "url(file://" + str(T / "fonts") + "/")
NAVY, NAVY2, GOLD = "#0f4c81", "#0a365d", "#e8a33d"
jobs = []
def page(name, body, w, h, transparent=False, css=""):
    html = (f"<!doctype html><html><head><meta charset='utf-8'><style>{FONTS}*{{margin:0;padding:0;box-sizing:border-box}}"
            f"html,body{{width:{w}px;height:{h}px;overflow:hidden;background:{'transparent' if transparent else NAVY}}}"
            f"body{{font-family:'Noto Sans Bengali',sans-serif}}{css}</style></head><body>{body}</body></html>")
    hp = OUT / f"{name}.html"; hp.write_text(html)
    jobs.append({"html": str(hp), "png": str(OUT / f"{name}.png"), "w": w, "h": h, "transparent": transparent})

svg, vw, vh = L.logo_html("#fff", "#fff")
page("logo_white_transparent", f"<div style='width:{vw}px;height:{vh}px'>{svg}</div>", vw, vh, True)
svg_n, _, _ = L.logo_html(NAVY, GOLD)
page("logo_navy_transparent", f"<div style='width:{vw}px;height:{vh}px'>{svg_n}</div>", vw, vh, True)

# profile: navy circle, white letters, gold frame
s = 860 / vw
svg_p, _, _ = L.logo_html("#fff", GOLD, scale=s)
page("profile_picture_1080",
     f"<div style='width:1080px;height:1080px;display:flex;align-items:center;justify-content:center;"
     f"background:radial-gradient(circle at 50% 42%, #1a5f9c 0%, {NAVY} 55%, {NAVY2} 100%)'>{svg_p}</div>", 1080, 1080)

# cover: logo left of centre block, tagline + exam chips right
s2 = 470 / vh
svg_c, _, _ = L.logo_html("#fff", GOLD, scale=s2)
cover = f"""<div style="width:1640px;height:624px;background:linear-gradient(120deg,{NAVY2} 0%,{NAVY} 55%,#17609e 100%);position:relative;color:#fff">
<div style="position:absolute;left:50%;top:0;transform:translateX(-50%);width:1060px;height:100%;display:flex;align-items:center;gap:46px">
<div style="flex:none">{svg_c}</div>
<div><div style="font-size:46px;font-weight:700;line-height:1.25">বিসিএস ও সকল সরকারি<br>চাকরির প্রস্তুতি</div>
<div style="font-size:27px;font-weight:600;color:#cfe0f0;letter-spacing:.5px;margin-top:6px">BCS &amp; Govt Job Preparation</div>
<div style="display:flex;gap:10px;margin-top:22px;flex-wrap:wrap">{''.join(f"<div style='border:2px solid rgba(255,255,255,.55);border-radius:40px;padding:2px 18px 5px;font-size:25px;font-weight:600'>{t}</div>" for t in ['বিসিএস','ব্যাংক','প্রাইমারি','শিক্ষক নিবন্ধন','৯ম–২০তম গ্রেড'])}</div>
<div style="margin-top:22px;font-size:26px;color:#f3d29b;font-weight:600">দিনের প্রশ্ন · বিগত প্রশ্নের ব্যাখ্যা · সাপ্তাহিক পরীক্ষা · মাসিক PDF</div></div></div></div>"""
page("facebook_cover_1640x624", cover, 1640, 624)

# pinned welcome post (1080x1350): casual, no routine list
s3 = 560 / vw
svg_w, _, _ = L.logo_html(NAVY, GOLD, scale=s3)
welcome = f"""<div style="width:1080px;height:1350px;background:#f6f3ec;color:#17213a;display:flex;flex-direction:column;align-items:center;padding:0 70px;text-align:center">
<div style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center">
<div>{svg_w}</div>
<div style="font-size:96px;font-weight:700;color:{NAVY};margin-top:10px;line-height:1.1">স্বাগতম 👋</div>
<div style="font-size:44px;font-weight:600;line-height:1.45;margin-top:26px">পড়ার শেষ নেই, অথচ কমন পড়ে না?<br><span style="color:{NAVY}">চলেন, একসাথে একটু স্মার্টলি পড়ি।</span></div></div>
<div style="width:1080px;height:120px;background:{NAVY};color:#fff;display:flex;align-items:center;justify-content:center;font-size:36px;font-weight:600">বিসিএস ও সকল সরকারি চাকরির প্রস্তুতি</div></div>"""
page("welcome_post_1080x1350", welcome, 1080, 1350, css="body{background:#f6f3ec}")
(OUT / "jobs.json").write_text(json.dumps(jobs))
subprocess.run(["node", str(T / "logo_render.cjs"), str(OUT / "jobs.json")], check=True)
for j in jobs: Path(j["html"]).unlink()
(OUT / "jobs.json").unlink()
