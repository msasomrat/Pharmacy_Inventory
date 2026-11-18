#!/usr/bin/env python3
"""CAAB special series: per-post folders (images + caption.txt) and model-test PDFs from caab/caab_series.json.
usage: caab_series.py   (paths are fixed relative to job_prep_bangla/)"""
import json, os, re, shutil, subprocess, sys
from pathlib import Path

T = Path(__file__).parent.resolve()
ROOT = T.parent
CD = Path(os.environ.get("CAAB_DIR", ROOT / "caab"))
DATA = json.loads((CD / "caab_series.json").read_text())
OUT = CD / "posts"

def short_src(t):
    """'বিমান বাংলাদেশ এয়ারলাইন্স লিমিটেড, পদের নামঃ X, তারিখঃ ০৮.০১.২০২১' -> 'বিমান: X ২০২১'"""
    if not t: return t
    t = re.sub(r"বিমান বাংলাদেশ এয়ারলাইন্স( লিমিটেড| লিঃ)?", "বিমান", t)
    t = re.sub(r"বেসামরিক বিমান চলাচল কর্তৃপক্ষ", "CAAB", t)
    t = re.sub(r",?\s*পদের নাম\s*[ঃ:]\s*", ": ", t)
    t = re.sub(r",?\s*(পরীক্ষার )?তারিখ\s*[ঃ:]\s*[০-৯]{1,2}[./-][০-৯]{1,2}[./-]([০-৯]{4})", r" \2", t)
    t = re.sub(r"\s+", " ", t).strip(" ,")
    return t
def fix(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k == "src" and isinstance(v, str): o[k] = short_src(v)
            else: fix(v)
    elif isinstance(o, list):
        for v in o: fix(v)
fix(DATA)

# reuse the poster helpers from posts.py (everything above its main loop)
sys.argv = [str(T / "posts.py"), str(OUT)]
src = (T / "posts.py").read_text().split("summary = []")[0]
g = {"__file__": str(T / "posts.py")}
exec(compile(src, "posts.py", "exec"), g)
page, slide_inner, mcq_inner, mcq_plain, write_caption, e, bn, LBL = (g[k] for k in
    ("page", "slide_inner", "mcq_inner", "mcq_plain", "write_caption", "e", "bn", "LBL"))
jobs = g["jobs"]
TAGS = "#CAAB #বেবিচক #বিমান_নিয়োগ #চাকরির_প্রস্তুতি #সরকারি_চাকরি"
SLUG = {"দিনের প্রশ্ন": "DinerProshno", "ক্যারোসেল": "Carousel", "৫ প্রশ্ন": "FiveMCQ", "ফাঁদ প্রশ্ন": "TrapQuestion",
        "বারবার আসা প্রশ্ন": "RepeatedQuestion", "মডেল টেস্ট": "ModelTest", "বার্তা": "Message"}

# keep the exam-notice post folder, rebuild the rest
for d in OUT.glob("*"):
    if d.is_dir() and not d.name.startswith("00_"): shutil.rmtree(d)

index = []
n = 0
for day in DATA["days"]:
    for p in day["posts"]:
        n += 1
        fmt = p["format"]
        f = OUT / f"{n:02d}_{day['date'][5:].replace('-', '')}_{'AM' if p['slot']=='সকাল' else 'PM'}_{SLUG.get(fmt, 'Post')}"
        f.mkdir(parents=True)
        cd = day.get("countdown", "")
        extra = None
        if fmt in ("দিনের প্রশ্ন", "ফাঁদ প্রশ্ন"):
            badge, cls = ("দিনের প্রশ্ন", "") if fmt == "দিনের প্রশ্ন" else ("ফাঁদ প্রশ্ন ⚠", "warn")
            page(f / "post.png", mcq_inner(p["mcq"]), badge, cls, "", cd)
        elif fmt == "৫ প্রশ্ন":
            ms = p["mcqs"]; k = len(ms) + 1
            page(f / "slide01.png", slide_inner(p["title"] + "\nসোয়াইপ করুন, উত্তর মিলিয়ে নিন কমেন্টে", cover=True), p.get("badge", "বিগত প্রশ্ন"), "gold", f"১/{bn(k)}", cd, cls="cover")
            for i, m in enumerate(ms, 2):
                page(f / f"slide{i:02d}.png", mcq_inner(m, "উত্তর লিখে রাখুন, মিলিয়ে নিন কমেন্টে"), f"প্রশ্ন {bn(i-1)}", "", f"{bn(i)}/{bn(k)}", cd)
            extra = "সঠিক উত্তর: " + ", ".join(f"{bn(i)}-{LBL[m['ans']]}" for i, m in enumerate(ms, 1))
        elif fmt in ("ক্যারোসেল", "বারবার আসা প্রশ্ন"):
            sl = p["slides"]; k = len(sl)
            for i, s in enumerate(sl, 1):
                page(f / f"slide{i:02d}.png", slide_inner(s, cover=(i == 1)), p.get("badge", "চিনে নিন"), "gold" if i == 1 else "",
                     f"{bn(i)}/{bn(k)}" if k > 1 else "", cd, cls="cover" if i == 1 else "")
        elif fmt == "মডেল টেস্ট":
            t = next(t for t in DATA["tests"] if t["id"] == p["test_id"])
            page(f / "post.png", slide_inner(f"{t['title']}\n{bn(len(t['questions']))}টি প্রশ্ন · {bn(t['minutes'])} মিনিট\nপ্রশ্ন + ব্যাখ্যাসহ উত্তরের PDF কমেন্টে", cover=True),
                 "মডেল টেস্ট", "warn", "", cd, cls="cover")
        else:  # বার্তা: good luck / how was the exam
            page(f / "post.png", slide_inner(p["slides"][0], cover=True), p.get("badge", "শুভকামনা"), "gold", "", cd, cls="cover")
        write_caption(f, p["caption"], p.get("hashtags") or TAGS, p.get("answer_comment"), extra)
        if fmt == "মডেল টেস্ট":
            pdf = CD / f"CAAB_Model_Test_{p['test_id']}.pdf"
            (f / "NOTE.txt").write_text(f"পোস্টের প্রথম কমেন্টে {pdf.name} ফাইলটা দিন (অথবা Google Drive লিংক)।\n")
        index.append((day["label"], p["slot"], p.get("time", ""), fmt, f.name))

(T / "postjobs.json").write_text(json.dumps(jobs))
subprocess.run(["node", str(T / "shots.cjs"), str(T / "postjobs.json")], check=True)
shutil.rmtree(T / "postjobs", ignore_errors=True); (T / "postjobs.json").unlink()

with open(OUT / "INDEX.txt", "w") as fh:
    fh.write("CAAB স্পেশাল সিরিজ: পোস্টের সূচি\nপ্রতিটা ফোল্ডারে ছবি (post.png / slideNN.png) আর caption.txt। উত্তরের কমেন্ট পোস্টের ২–৩ ঘণ্টা পর।\n\n")
    fh.write("১৮ নভেম্বর | রাত | ৮:০০ | পরীক্ষার তারিখ | 00_Nov18_ExamNotice\n")
    for lab, slot, tm, fmt, name in index:
        fh.write(f"{lab} | {slot} | {tm} | {fmt} | {name}\n")

# model-test PDFs + suggestion PDF via render.py
os.environ["WEEKS_DIR"] = str(T / "weeks"); os.environ["HTML_DIR"] = str(T / "_caab_html")
sys.argv = [str(T / "render.py"), str(CD)]
R = {"__name__": "render_mod", "__file__": str(T / "render.py")}
exec(compile((T / "render.py").read_text(), "render.py", "exec"), R)
H = Path(os.environ["HTML_DIR"]); H.mkdir(exist_ok=True)
out_pdfs = []
for t in DATA["tests"]:
    w = {"week": t["id"], "title": t["title"], "exam": t["questions"], "label": f"CAAB স্পেশাল · মডেল টেস্ট {bn(t['id'])}",
         "kind": "মডেল টেস্ট", "minutes": t["minutes"]}
    h = R["head"](t["title"]) + R["exam_html"](w).replace("<div class='page-break'></div>", "", 1) + "<div class='page-break'></div>" + R["answers_html"](w) + "</body></html>"
    hp = H / f"test{t['id']}.html"; hp.write_text(h); out_pdfs.append((hp, CD / f"CAAB_Model_Test_{t['id']}.pdf"))
# suggestion PDF: notes + both tests
sw = {"week": 0, "title": "CAAB সাজেশন: এভিয়েশন ও বিমানের গুরুত্বপূর্ণ তথ্য", "topics": {}, "notes": DATA["suggestion_notes"]}
notes = R["notes_html"](sw).replace("সপ্তাহ ০ · রিভিশন নোট", "CAAB সাজেশন").replace("মাস ১ · সপ্তাহ ০", "CAAB স্পেশাল")
parts = [R["head"]("CAAB সাজেশন"), notes]
for t in DATA["tests"]:
    w = {"week": t["id"], "title": t["title"], "exam": t["questions"], "label": f"মডেল টেস্ট {bn(t['id'])}", "kind": "মডেল টেস্ট", "minutes": t["minutes"]}
    parts.append(R["exam_html"](w))
for t in DATA["tests"]:
    w = {"week": t["id"], "title": t["title"], "exam": t["questions"], "label": f"মডেল টেস্ট {bn(t['id'])}"}
    parts.append("<div class='page-break'></div>" + R["answers_html"](w))
hp = H / "suggestion.html"; hp.write_text("".join(parts) + "</body></html>"); out_pdfs.append((hp, CD / "CAAB_Suggestion.pdf"))
for hp, pdf in out_pdfs:
    subprocess.run(["node", str(T / "pdf.cjs"), str(hp), str(pdf)], check=True)
shutil.rmtree(H)
print(n, "posts,", len(jobs), "images,", len(out_pdfs), "PDFs")
