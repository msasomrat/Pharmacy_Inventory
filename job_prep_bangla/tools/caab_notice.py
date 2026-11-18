#!/usr/bin/env python3
"""CAAB MCQ exam-date notice carousel (from the CAAB notice dated 16 Nov 2026). usage: caab_notice.py OUT_DIR"""
import json, subprocess, sys
from pathlib import Path

T = Path(__file__).parent
OUT = Path(sys.argv[1]).resolve(); OUT.mkdir(parents=True, exist_ok=True)
FONTS = (T / "fonts" / "local.css").read_text().replace("url(", "url(file://" + str(T / "fonts") + "/")
NAVY, GOLD, CREAM, RED = "#0f4c81", "#e8a33d", "#f6f3ec", "#c0392b"
LOGO_W = "file://" + str((T.parent / "branding" / "logo_white_tight.png").resolve())

CSS = FONTS + f"""*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:1080px;height:1350px;overflow:hidden}}
body{{font-family:'Noto Sans Bengali',sans-serif;background:{CREAM};color:#17213a;display:flex;flex-direction:column}}
.top{{padding:56px 64px 0;display:flex;justify-content:space-between;align-items:center}}
.badge{{background:{RED};color:#fff;font-weight:700;font-size:38px;padding:6px 26px 9px;border-radius:40px}}
.cnt{{font-size:34px;color:#2f3a52;font-weight:700}}
.main{{flex:1;padding:20px 64px 24px;display:flex;flex-direction:column;justify-content:center}}
h1{{font-size:78px;font-weight:800;line-height:1.2;color:{NAVY}}}
.sub{{font-size:38px;color:#0b1222;font-weight:600;margin:10px 0 30px}}
.card{{background:#fff;border-radius:24px;border-left:18px solid {NAVY};padding:24px 32px;margin-bottom:26px}}
.card .d{{font-size:66px;font-weight:800;color:{NAVY};line-height:1.15}}
.card .t{{font-size:42px;font-weight:700;color:#0b1222}}
.card .p{{font-size:39px;font-weight:600;margin-top:8px;line-height:1.35;color:#0b1222}}
.card .n{{font-size:36px;color:#0b1222;font-weight:600;margin-top:6px}}
.note{{background:#fff4e0;border-radius:20px;padding:20px 28px;font-size:36px;font-weight:700;line-height:1.45;color:#0b1222}}
.foot{{height:132px;background:{NAVY};color:#fff;display:flex;justify-content:space-between;align-items:center;padding:0 64px;font-size:30px;font-weight:600}}
.foot .s{{color:#f3d29b}}
table{{width:100%;border-collapse:collapse;font-size:42px}}
td{{font-weight:600;padding:14px 8px;border-bottom:3px dashed #d8d2c4;line-height:1.3;color:#0b1222}} td.r{{text-align:right;color:{NAVY};font-weight:800;white-space:nowrap}}
"""
def doc(body, n):
    return (f"<!doctype html><html lang='bn'><head><meta charset='utf-8'><style>{CSS}</style></head><body>"
            f"<div class='top'><span class='badge'>পরীক্ষার তারিখ</span><span class='cnt'>{n}</span></div>{body}"
            f"<div class='foot'><img src='{LOGO_W}' style='height:108px;display:block'><span class='s'>সূত্র: caab.gov.bd · ১৬ নভেম্বর ২০২৬</span></div></body></html>")

s1 = doc("""<div class='main'><h1>CAAB নিয়োগ:<br>MCQ পরীক্ষার তারিখ প্রকাশ</h1>
<div class='sub'>বেসামরিক বিমান চলাচল কর্তৃপক্ষ (বেবিচক)</div>
<div class='card'><div class='d'>২৭ নভেম্বর, শুক্রবার</div><div class='t'>বিকাল ৩:০০টা</div>
<div class='p'><b>সিনিয়র অফিসার</b> (পোস্ট কোড ১০৬)</div><div class='n'>প্রার্থী ৩৩,১২৮ জন · ঢাকার ৮টি কেন্দ্র</div></div>
<div class='card' style='border-left-color:#e8a33d'><div class='d'>৪ ডিসেম্বর, শুক্রবার</div><div class='t'>বিকাল ৩:০০টা</div>
<div class='p'><b>আরও ১৮টি পদ</b> (২য় ও ৩য় ছবিতে তালিকা)</div><div class='n'>মোট প্রার্থী ১৭,৫০৫ জন · ঢাকার ৫টি কেন্দ্র</div></div>
<div class='note'>⚠️ রঙিন প্রবেশপত্র অবশ্যই সঙ্গে আনতে হবে। প্রবেশপত্রের তথ্য টেলিটক SMS-এ পাঠানো হয়েছে।</div></div>""", "১/৩")

posts = [("১০৭", "মেডিক্যাল অফিসার", "১,০৭০"), ("১০৮", "প্রকিউরমেন্ট অফিসার", "২,৫৬৩"), ("১০৯", "সহকারী মেইনটেন্যান্স প্রকৌশলী", "২২১"),
         ("১১০", "সহকারী প্রোগ্রামার", "১,১৮৬"), ("১১১", "এরোড্রোম অফিসার (এটিএম)", "৩,৭৪৪"), ("১১২", "সিনিয়র কার্টোগ্রাফার", "১২৫"),
         ("১১৩", "সিএনএস প্রকৌশলী", "১,৬২২"), ("১১৪", "এয়ার ট্রান্সপোর্টেশন অফিসার", "৩১৫"), ("১১৬", "ইন্সপেক্টর (অপস)", "৫৭৫"),
         ("১২২", "নিরাপত্তা কর্মকর্তা", "১,৪৭১"), ("১১৭", "এয়ারওয়ার্দিনেস ইন্সপেক্টর (এরোস্পেস)", "৪৫০"), ("১১৮", "এয়ারওয়ার্দিনেস ইন্সপেক্টর (এভিয়নিক্স)", "৫৫"),
         ("১২০", "অর্থনীতিবিদ", "২১৩"), ("১২১", "ফায়ার অফিসার", "১৫৫"), ("১২৩", "হিসাবরক্ষণ কর্মকর্তা", "৭৫৪"),
         ("১২৪", "নিরীক্ষা কর্মকর্তা", "৬২৬"), ("১২৫", "সহকারী প্রকৌশলী (সিভিল)", "১,৫৭২"), ("১২৬", "সহকারী প্রকৌশলী (ই/এম)", "৭৮৮")]
def table_slide(part, n):
    rows = "".join(f"<tr><td>{nm}</td><td class='r'>{k} জন</td></tr>" for c, nm, k in part)
    return doc(f"""<div class='main' style='justify-content:flex-start'><h1 style='font-size:62px'>৪ ডিসেম্বরের পরীক্ষা</h1>
<div class='sub' style='margin-bottom:10px'>শুক্রবার বিকাল ৩টা · পদ ও প্রার্থী সংখ্যা</div>
<table>{rows}</table></div>""", n)
s2 = table_slide(posts[:9], "২/৩")
s3 = table_slide(posts[9:], "৩/৩")

jobs = []
for name, h in (("slide01", s1), ("slide02", s2), ("slide03", s3)):
    hp = OUT / f"{name}.html"; hp.write_text(h)
    jobs.append({"html": str(hp), "png": str(OUT / f"{name}.png"), "w": 1080, "h": 1350})
(OUT / "jobs.json").write_text(json.dumps(jobs))
subprocess.run(["node", str(T / "logo_render.cjs"), str(OUT / "jobs.json")], check=True)
for j in jobs: Path(j["html"]).unlink()
(OUT / "jobs.json").unlink()
