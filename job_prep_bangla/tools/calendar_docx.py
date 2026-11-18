#!/usr/bin/env python3
"""Content calendar DOCX (ready-to-post captions) from weeks/week*.json. usage: calendar_docx.py out.docx"""
import json, os, sys
from pathlib import Path
from docx import Document
from docx.shared import Pt, RGBColor
from docx.oxml.ns import qn

SP = Path(__file__).parent
WEEKS_DIR = Path(os.environ.get("WEEKS_DIR", SP / "weeks"))
FONT = "Kalpurush"
BD = str.maketrans("0123456789", "০১২৩৪৫৬৭৮৯")
bn = lambda n: str(n).translate(BD)
LBL = ["ক", "খ", "গ", "ঘ"]
BRAND = os.environ.get("BRAND", "চাকরির বাংলা প্রস্তুতি")

weeks = sorted((json.load(open(p)) for p in WEEKS_DIR.glob("week*.json")), key=lambda w: w["week"])
doc = Document()

def setfont(run, size=None, bold=None, color=None):
    run.font.name = FONT
    rpr = run._element.get_or_add_rPr()
    rf = rpr.find(qn("w:rFonts"))
    if rf is None:
        rf = rpr.makeelement(qn("w:rFonts"), {}); rpr.append(rf)
    for a in ("w:ascii", "w:hAnsi", "w:cs", "w:eastAsia"):
        rf.set(qn(a), FONT)
    if size:
        run.font.size = Pt(size)
        szcs = rpr.makeelement(qn("w:szCs"), {qn("w:val"): str(int(size * 2))}); rpr.append(szcs)
    if bold is not None:
        run.bold = bold
        if bold: rpr.append(rpr.makeelement(qn("w:bCs"), {}))
    if color: run.font.color.rgb = RGBColor.from_string(color)

def para(text="", size=12, bold=False, color=None, style=None):
    p = doc.add_paragraph(style=style)
    for i, line in enumerate(str(text).split("\n")):
        if i: p.add_run().add_break()
        setfont(p.add_run(line), size, bold, color)
    return p

def heading(text, level):
    p = doc.add_heading(level=level)
    setfont(p.add_run(text), {0: 22, 1: 17, 2: 14, 3: 12.5}[level], True, "0F4C81")

def label(name, value, size=12):
    if not value: return
    p = doc.add_paragraph()
    setfont(p.add_run(f"{name}: "), size, True, "8A5A00")
    for i, line in enumerate(str(value).split("\n")):
        if i: p.add_run().add_break()
        setfont(p.add_run(line), size)

def mcq_text(m):
    src = f" [{m['src']}]" if m.get("src") else ""
    opts = "   ".join(f"{LBL[i]}) {o}" for i, o in enumerate(m["opts"]))
    return f"{m['q'].split(' / ')[0]}{src}\n{opts}"

heading(f"{BRAND}: কনটেন্ট ক্যালেন্ডার ({'মাস ১'})", 0)
para("প্রতিটি পোস্টের ছবি/স্লাইডের লেখা, ক্যাপশন, হ্যাশট্যাগ আর উত্তরের কমেন্ট নিচে দেওয়া আছে। কপি করে সরাসরি পোস্ট করা যাবে।", 12)
para("সময়: সকাল ৭–৯টায় 'দিনের প্রশ্ন', রাত ৮–১১টায় মূল পোস্ট। উত্তরের কমেন্ট দিন ২–৩ ঘণ্টা পর। শুক্রবার সাপ্তাহিক পরীক্ষার PDF/Google Form।", 12)

for w in weeks:
    doc.add_page_break()
    heading(w["title"], 1)
    t = w["topics"]
    para(f"ব্যাকরণ: {t.get('grammar','')}  |  শব্দভান্ডার: {t.get('vocab','')}  |  সাহিত্য: {t.get('literature','')}", 11, color="555555")
    tbl = doc.add_table(rows=1, cols=3); tbl.style = "Light Grid Accent 1"
    for c, h in zip(tbl.rows[0].cells, ["দিন", "ধরন", "বিষয়"]):
        c.text = ""; setfont(c.paragraphs[0].add_run(h), 11, True)
    for p in w["posts"]:
        row = tbl.add_row().cells
        for c, v in zip(row, [p["day"], p["format"], p["title"]]):
            c.text = ""; setfont(c.paragraphs[0].add_run(v), 11)

    heading("সকালের 'দিনের প্রশ্ন'", 2)
    for d in w.get("daily_mcq", []):
        heading(d["day"], 3)
        label("পোস্ট", "📌 দিনের প্রশ্ন\n" + mcq_text(d) + "\n\nকমেন্টে আপনার উত্তর লিখুন 👇")
        label("উত্তরের কমেন্ট", d.get("comment"))

    heading("মূল পোস্ট", 2)
    for p in w["posts"]:
        heading(f"{p['day']}: {p['format']}: {p['title']}", 3)
        if p.get("slides"):
            label("স্লাইড", "\n".join(f"স্লাইড {bn(i)}: {s}" for i, s in enumerate(p["slides"], 1)))
        if p.get("script"):
            label("রিল স্ক্রিপ্ট", "\n".join("▸ " + s for s in p["script"]))
        if p.get("mcq"):
            label("প্রশ্ন", mcq_text(p["mcq"]) + f"\n(সঠিক উত্তর: {LBL[p['mcq']['ans']]})")
        if p.get("mcqs"):
            label("প্রশ্নগুলো", "\n\n".join(f"{bn(i)}. " + mcq_text(m) + f"\n(সঠিক: {LBL[m['ans']]})" for i, m in enumerate(p["mcqs"], 1)))
        if p.get("exams"):
            label("যেসব পরীক্ষায় এসেছে", "\n".join("• " + x for x in p["exams"]))
        label("ছবির লেখা", p.get("design_text"))
        label("ক্যাপশন", p.get("caption"))
        label("হ্যাশট্যাগ", p.get("hashtags"))
        label("উত্তরের কমেন্ট", p.get("answer_comment"))

doc.save(sys.argv[1] if len(sys.argv) > 1 else SP / "calendar.docx")
print("ok")
