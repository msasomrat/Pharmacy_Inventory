#!/usr/bin/env python3
"""Facebook profile picture + cover for নিয়োগ দরবার. usage: branding.py OUT_DIR  (then node shots.js jobs.json)"""
import json, sys
from pathlib import Path

T = Path(__file__).parent
OUT = Path(sys.argv[1]).resolve(); OUT.mkdir(parents=True, exist_ok=True)
FONTS = (T / "fonts" / "local.css").read_text().replace("url(", "url(file://" + str(T / "fonts") + "/")
NAVY, NAVY2, GOLD, CREAM = "#0f4c81", "#0a365d", "#e8a33d", "#f6f3ec"
READY = "<script>document.fonts.ready.then(()=>document.body.dataset.ready='1')</script>"

def arch(w, stroke, color=GOLD):
    # দরবারের খিলান: pointed arch with a dome finial
    return f"""<svg width="{w}" viewBox="0 0 120 130" fill="none" stroke="{color}" stroke-width="{stroke}" stroke-linecap="round" stroke-linejoin="round">
      <circle cx="60" cy="9" r="5" fill="{color}" stroke="none"/>
      <path d="M14 126 V64 Q14 30 60 16 Q106 30 106 64 V126"/>
      <path d="M34 126 V72 Q34 48 60 38 Q86 48 86 72 V126" opacity=".55"/>
      <path d="M4 126 H116"/></svg>"""

BASE = FONTS + f"""*{{margin:0;padding:0;box-sizing:border-box}} body{{font-family:'Hind Siliguri',sans-serif;overflow:hidden}}"""

profile = f"""<!doctype html><html><head><meta charset="utf-8"><style>{BASE}
body{{width:1080px;height:1080px;background:{NAVY};display:flex;align-items:center;justify-content:center}}
.c{{width:1080px;height:1080px;border-radius:50%;background:radial-gradient(circle at 50% 38%, #1a5f9c 0%, {NAVY} 55%, {NAVY2} 100%);
    display:flex;flex-direction:column;align-items:center;justify-content:center;gap:0}}
.n1{{color:#fff;font-weight:700;font-size:210px;line-height:1;margin-top:-10px}}
.n2{{color:{GOLD};font-weight:700;font-size:210px;line-height:1.05}}
.t{{color:#cfe0f0;font-weight:600;font-size:46px;margin-top:22px;letter-spacing:1px}}
</style></head><body><div class="c">{arch(190, 6)}<div class="n1">নিয়োগ</div><div class="n2">দরবার</div><div class="t">বিসিএস · সরকারি চাকরি</div></div>{READY}</body></html>"""

cover = f"""<!doctype html><html><head><meta charset="utf-8"><style>{BASE}
body{{width:1640px;height:624px;background:linear-gradient(120deg,{NAVY2} 0%,{NAVY} 55%,#17609e 100%);position:relative;color:#fff}}
.pat{{position:absolute;inset:0;opacity:.07;display:flex;justify-content:space-between;align-items:flex-end;padding:0 10px}}
.wrap{{position:absolute;left:50%;top:0;transform:translateX(-50%);width:1060px;height:100%;display:flex;align-items:center;gap:40px}}
.l{{flex:none}}
.name{{font-weight:700;font-size:118px;line-height:1}} .name span{{color:{GOLD}}}
.tag{{font-size:40px;font-weight:600;color:#dbe8f5;margin-top:10px}}
.ex{{display:flex;gap:12px;margin-top:26px;flex-wrap:wrap}}
.ex div{{border:2px solid rgba(255,255,255,.55);border-radius:40px;padding:2px 20px 5px;font-size:27px;font-weight:600}}
.feat{{margin-top:24px;font-size:28px;color:#f3d29b;font-weight:600}}
</style></head><body>
<div class="pat">{''.join(arch(150, 4, '#ffffff') for _ in range(10))}</div>
<div class="wrap"><div class="l">{arch(220, 5)}</div>
<div><div class="name">নিয়োগ <span>দরবার</span></div>
<div class="tag">বিসিএস ও সকল সরকারি চাকরির প্রস্তুতি</div>
<div class="ex"><div>বিসিএস</div><div>ব্যাংক</div><div>প্রাইমারি</div><div>শিক্ষক নিবন্ধন</div><div>৯ম–২০তম গ্রেড</div></div>
<div class="feat">দিনের প্রশ্ন · বিগত প্রশ্নের ব্যাখ্যা · সাপ্তাহিক পরীক্ষা · মাসিক PDF</div></div></div>{READY}</body></html>"""

# circle-crop preview of the profile and a phone-crop preview of the cover, for checking only
jobs = []
for name, html, w, h in [("profile_picture_1080.png", profile, 1080, 1080), ("facebook_cover_1640x624.png", cover, 1640, 624)]:
    hp = OUT / (name + ".html"); hp.write_text(html)
    jobs.append({"html": str(hp), "png": str(OUT / name), "w": w, "h": h})
(OUT / "jobs.json").write_text(json.dumps(jobs))
print("ok")
