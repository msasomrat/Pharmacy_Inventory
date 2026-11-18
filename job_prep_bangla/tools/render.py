#!/usr/bin/env python3
"""Build month-1 HTML (monthly PDF + 4 weekly exam PDFs) and the content-calendar DOCX from weeks/week*.json."""
import json, html, sys, os
from pathlib import Path

SP = Path(__file__).parent
WEEKS_DIR = Path(os.environ.get("WEEKS_DIR", SP / "weeks"))
HTML_DIR = Path(os.environ.get("HTML_DIR", SP / "html"))
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else SP / "out"
BRAND = os.environ.get("BRAND", "নিয়োগ দরবার")
MONTH = "মাস ১"
HTML_DIR.mkdir(exist_ok=True); OUT.mkdir(parents=True, exist_ok=True)

BD = str.maketrans("0123456789", "০১২৩৪৫৬৭৮৯")
def bn(n): return str(n).translate(BD)
LBL = ["ক", "খ", "গ", "ঘ"]
TOPIC_BN = {"grammar": "ব্যাকরণ", "vocab": "শব্দভান্ডার", "literature": "সাহিত্য"}
e = lambda s: html.escape(str(s or ""))

weeks = [json.load(open(p)) for p in sorted(WEEKS_DIR.glob("week*.json"))]
weeks.sort(key=lambda w: w["week"])

LOGO_W = "file://" + str((SP.parent / "branding" / "logo_white_tight.png").resolve())
LOGO_N = "file://" + str((SP.parent / "branding" / "logo_navy_tight.png").resolve())
FONT_CSS = (SP / "fonts" / "local.css").read_text().replace("url(", "url(file://" + str(SP / "fonts") + "/")
CSS = FONT_CSS + """
@page { size: A4; margin: 13mm 13mm 14mm 13mm; }
:root { --ink:#1d2433; --muted:#3d4760; --line:#d9dee8; --brand:#0f4c81; --accent:#e8a33d; --soft:#eef4fa; --ok:#16794c; }
* { box-sizing: border-box; }
html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
body { font-family: 'Noto Sans Bengali', sans-serif; font-weight: 500; color: #0b1222; font-size: 10.6pt; line-height: 1.55; margin: 0; }
h1,h2,h3,.sans { font-family: 'Noto Sans Bengali', sans-serif; }
.page-break { break-before: page; }
.runhead { font-family:'Noto Sans Bengali'; font-size:9pt; font-weight:600; color:#2f3a52; border-bottom:1px solid var(--line); padding-bottom:4px; margin-bottom:10px; display:flex; justify-content:space-between; align-items:flex-end; }

/* cover */
.cover { height: 265mm; display:flex; flex-direction:column; justify-content:space-between; }
.cover .band { background: var(--brand); color:#fff; border-radius: 6px; padding: 26px 28px; }
.cover .band .kicker { font-family:'Noto Sans Bengali'; letter-spacing:.5px; opacity:.85; font-size:12pt; }
.cover .band h1 { font-size: 34pt; margin: 6px 0 4px; line-height:1.2; }
.cover .band .sub { font-size: 14pt; font-family:'Noto Sans Bengali'; }
.cover .accent { height:6px; width:90px; background:var(--accent); border-radius:3px; margin:14px 0 0; }
.weeklist { display:grid; grid-template-columns:1fr 1fr; gap:10px; }
.weekcard { border:1px solid var(--line); border-left:5px solid var(--brand); border-radius:5px; padding:10px 12px; }
.weekcard .n { font-family:'Noto Sans Bengali'; font-weight:700; color:var(--brand); }
.weekcard div { font-size:9.8pt; }
.howto { background: var(--soft); border-radius:6px; padding: 12px 16px; }
.howto h3 { margin:0 0 6px; color:var(--brand); }
.howto ol { margin:0; padding-left: 20px; }

/* week header */
.weekhead { background: var(--brand); color:#fff; border-radius:6px; padding:12px 16px; margin-bottom:12px; }
.weekhead .k { font-family:'Noto Sans Bengali'; font-size:10pt; opacity:.85; }
.weekhead h2 { margin:2px 0 0; font-size:19pt; }
.topics { display:flex; gap:8px; flex-wrap:wrap; margin-top:6px; }
.chip { font-family:'Noto Sans Bengali'; font-size:9pt; background:rgba(255,255,255,.16); border-radius:20px; padding:1px 10px; }

/* notes */
.note { margin-bottom: 10px; break-inside: auto; }
.note h3 { font-size: 12.5pt; color: var(--brand); border-bottom: 2px solid var(--accent); display:inline-block; margin: 6px 0 6px; padding-bottom:1px; }
.note ul { margin: 0 0 6px; padding-left: 18px; columns: 2; column-gap: 22px; }
.note li { margin-bottom: 3px; break-inside: avoid; }
.tables { display:flex; gap:12px; align-items:flex-start; }
.tables table { flex:1; }
table.t { border-collapse: collapse; width:100%; font-size: 9.8pt; margin: 4px 0 8px; }
table.t th { background: var(--soft); font-family:'Noto Sans Bengali'; text-align:left; }
table.t th, table.t td { border: 1px solid var(--line); padding: 3px 7px; vertical-align: top; }

/* exam */
.exambox { border:1.5px solid var(--brand); border-radius:6px; padding:8px 14px; margin-bottom:10px; display:flex; justify-content:space-between; align-items:center; }
.exambox h2 { margin:0; font-size:16pt; color:var(--brand); }
.exambox .meta { font-family:'Noto Sans Bengali'; font-size:9.5pt; text-align:right; color:var(--muted); }
.meta b { color: var(--ink); }
.namerow { font-family:'Noto Sans Bengali'; font-size:9.5pt; display:flex; gap:20px; margin-bottom:10px; }
.namerow span { flex:1; border-bottom:1px dotted #999; padding-bottom:2px; }
.qs { columns: 2; column-gap: 20px; column-rule: 1px solid var(--line); }
.q { break-inside: avoid; margin-bottom: 9px; }
.q .qt { font-weight: 600; }
.q .qn { font-family:'Noto Sans Bengali'; font-weight:700; color:var(--brand); margin-right:3px; }
.src { font-family:'Noto Sans Bengali'; font-size: 8.4pt; color: #3d4760; font-weight:400; white-space: normal; }
.opts { display:grid; grid-template-columns: 1fr 1fr; gap: 1px 10px; margin-top:2px; padding-left: 16px; font-size:10.2pt; }
.lbl { display:inline-block; width:15px; height:15px; line-height:14px; border:1px solid #777; border-radius:50%; text-align:center; font-family:'Noto Sans Bengali'; font-size:8pt; margin-right:4px; }
.sec { column-span: all; font-family:'Noto Sans Bengali'; font-weight:700; font-size:10pt; color:#fff; background:var(--brand); border-radius:3px; padding:1px 8px; margin: 2px 0 7px; display:inline-block; }
.score { margin-top:10px; font-family:'Noto Sans Bengali'; font-size:9.5pt; border:1px dashed var(--muted); border-radius:5px; padding:6px 12px; display:flex; gap:24px; }

/* answers */
.keygrid { display:grid; grid-template-columns: repeat(13, 1fr); border:1px solid var(--line); border-radius:4px; overflow:hidden; margin: 4px 0 12px; font-family:'Noto Sans Bengali'; font-size:9.5pt; }
.keygrid div { text-align:center; padding:2px 0; border-right:1px solid var(--line); border-bottom:1px solid var(--line); }
.keygrid div b { color: var(--ok); }
.exps { columns: 2; column-gap: 20px; column-rule: 1px solid var(--line); }
.x { break-inside: avoid; margin-bottom: 8px; font-size: 9.9pt; }
.x .xq { font-weight:600; }
.x .xa { font-family:'Noto Sans Bengali'; color: var(--ok); font-weight:700; }
.x .why { margin: 1px 0; }
.x ul { margin: 1px 0 0; padding-left: 16px; }
.x li { margin: 0; }
.x li::marker { content: "➕ "; color: var(--accent); font-size: 8pt; }
h2.part { font-size: 17pt; color: var(--brand); margin: 0 0 4px; }
.subtle { color: var(--muted); font-size: 9.5pt; font-family:'Noto Sans Bengali'; margin-bottom: 10px; }
"""

def head(title):
    return f"<!doctype html><html lang='bn'><head><meta charset='utf-8'><title>{e(title)}</title><style>{CSS}</style></head><body>"

def runhead(left):
    return f"<div class='runhead'><img src='{LOGO_N}' style='height:11mm;display:block'><span>{e(left)}</span></div>"

def week_header(w):
    t = w["topics"]
    chips = "".join(f"<span class='chip'>{e(TOPIC_BN[k])}: {e(t[k])}</span>" for k in ("grammar", "vocab", "literature") if t.get(k))
    return f"<div class='weekhead'><div class='k'>{e(MONTH)} · সপ্তাহ {bn(w['week'])}</div><h2>{e(w['title'])}</h2><div class='topics'>{chips}</div></div>"

def render_table(rows):
    if not rows: return ""
    hdr, body = rows[0], rows[1:]
    def tbl(part):
        th = "".join(f"<th>{e(c)}</th>" for c in hdr)
        trs = "".join("<tr>" + "".join(f"<td>{e(c)}</td>" for c in r) + "</tr>" for r in part)
        return f"<table class='t'><thead><tr>{th}</tr></thead><tbody>{trs}</tbody></table>"
    if len(hdr) <= 2 and len(body) > 8:
        half = (len(body) + 1) // 2
        return f"<div class='tables'>{tbl(body[:half])}{tbl(body[half:])}</div>"
    return tbl(body)

def notes_html(w):
    out = [runhead(f"সপ্তাহ {bn(w['week'])} · রিভিশন নোট"), week_header(w)]
    for n in w["notes"]:
        lis = "".join(f"<li>{e(b)}</li>" for b in n.get("bullets", []))
        out.append(f"<div class='note'><h3>{e(n['heading'])}</h3>{'<ul>'+lis+'</ul>' if lis else ''}{render_table(n.get('table'))}</div>")
    return "".join(out)

def exam_html(w):
    n = len(w["exam"])
    out = [f"<div class='page-break'></div>", runhead(f"সপ্তাহ {bn(w['week'])} · সাপ্তাহিক পরীক্ষা"),
           f"<div class='exambox'><div><div class='sans' style='font-size:9.5pt;color:var(--muted)'>{e(MONTH)} · সপ্তাহ {bn(w['week'])}</div><h2>সাপ্তাহিক পরীক্ষা: {e(w['title'].split(':',1)[-1].strip())}</h2></div>"
           f"<div class='meta'>সময়: <b>{bn(15)} মিনিট</b><br>পূর্ণমান: <b>{bn(n)}</b><br>প্রতিটি ভুলের জন্য <b>০.৫০</b> কাটা যাবে</div></div>",
           "<div class='namerow'><span>নাম:</span><span>তারিখ:</span><span>প্রাপ্ত নম্বর:</span></div>", "<div class='qs'>"]
    last = None
    for i, q in enumerate(w["exam"], 1):
        if q.get("topic") != last:
            last = q.get("topic"); out.append(f"<div class='sec'>{e(TOPIC_BN.get(last, last))}</div>")
        src = f" <span class='src'>[{e(q['src'])}]</span>" if q.get("src") else ""
        opts = "".join(f"<div><span class='lbl'>{LBL[j]}</span>{e(o)}</div>" for j, o in enumerate(q["opts"]))
        out.append(f"<div class='q'><div class='qt'><span class='qn'>{bn(i)}.</span>{e(q['q'].split(' / ')[0])}{src}</div><div class='opts'>{opts}</div></div>")
    out.append("</div>")
    out.append("<div class='score'><span>সঠিক: ______</span><span>ভুল: ______</span><span>নম্বর = সঠিক − (ভুল × ০.৫০) = ______</span></div>")
    return "".join(out)

def answers_html(w, with_runhead=True):
    out = []
    if with_runhead: out.append(runhead(f"সপ্তাহ {bn(w['week'])} · উত্তর ও ব্যাখ্যা"))
    out.append(f"<h2 class='part'>সপ্তাহ {bn(w['week'])}: উত্তরমালা ও ব্যাখ্যা</h2><div class='subtle'>{e(w['title'])}</div>")
    cells = "".join(f"<div>{bn(i)}. <b>{LBL[q['ans']]}</b></div>" for i, q in enumerate(w["exam"], 1))
    out.append(f"<div class='keygrid'>{cells}</div><div class='exps'>")
    for i, q in enumerate(w["exam"], 1):
        more = "".join(f"<li>{e(m)}</li>" for m in q.get("more", []))
        qs = q['q'].split(' / ')
        alt = f"<div class='src'>অন্যভাবেও এসেছে: {e(' / '.join(qs[1:]))}</div>" if len(qs) > 1 else ""
        out.append(f"<div class='x'><div class='xq'>{bn(i)}. {e(qs[0])}</div>{alt}"
                   f"<div class='xa'>✔ {LBL[q['ans']]}) {e(q['opts'][q['ans']])}</div>"
                   f"<div class='why'>{e(q.get('why'))}</div>{'<ul>'+more+'</ul>' if more else ''}</div>")
    out.append("</div>")
    return "".join(out)

def cover_html():
    cards = "".join(f"<div class='weekcard'><div class='n'>সপ্তাহ {bn(w['week'])}</div><div>{e(w['title'].split(':',1)[-1].strip())}</div></div>" for w in weeks)
    total_q = sum(len(w["exam"]) for w in weeks)
    return (f"<div class='cover'><div class='band'><div class='kicker'>বিসিএস ও সকল সরকারি চাকরির প্রস্তুতি</div><img src='{LOGO_W}' style='height:62mm;display:block;margin:10px 0 8px'><div class='sub' style='font-size:18pt;font-weight:700'>মাসিক প্রস্তুতি সিরিজ</div>"
            f"<div class='sub'>{e(MONTH)} · বাংলা ভাষা ও সাহিত্য · বিসিএস, ব্যাংক, প্রাইমারি ও অন্যান্য নিয়োগ পরীক্ষা</div><div class='accent'></div></div>"
            f"<div class='weeklist'>{cards}</div>"
            f"<div class='howto'><h3>এই PDF যেভাবে ব্যবহার করবেন</h3><ol>"
            f"<li><b>রিভিশন নোট</b> পড়ুন: প্রতিটি লাইন বিগত পরীক্ষায় আসা তথ্য থেকে বাছাই করা।</li>"
            f"<li><b>সাপ্তাহিক পরীক্ষা</b> দিন: ১৫ মিনিট সময় ধরে, উত্তর না দেখে। মোট {bn(len(weeks))}টি পরীক্ষা, {bn(total_q)}টি প্রশ্ন।</li>"
            f"<li><b>উত্তর ও ব্যাখ্যা</b> মিলিয়ে নিন: প্রতিটি ব্যাখ্যার ➕ চিহ্নের তথ্যগুলোও পরীক্ষায় আসে। একটি প্রশ্ন পড়লে কয়েকটি প্রশ্নের উত্তর জানা হয়ে যায়।</li>"
            f"<li>যে প্রশ্ন ভুল হয়েছে, সপ্তাহ শেষে শুধু সেগুলো আবার দেখুন।</li></ol></div></div>")

def build():
    # monthly
    parts = [head(f"{BRAND} — {MONTH}"), cover_html()]
    for w in weeks:
        parts.append("<div class='page-break'></div>" + notes_html(w))
        parts.append(exam_html(w))
    parts.append("<div class='page-break'></div>")
    for k, w in enumerate(weeks):
        if k: parts.append("<div class='page-break'></div>")
        parts.append(answers_html(w))
    parts.append("</body></html>")
    (HTML_DIR / "monthly.html").write_text("".join(parts))
    # weekly exam files: exam, then answers on a new page
    for w in weeks:
        h = head(f"সপ্তাহ {bn(w['week'])} পরীক্ষা") + exam_html(w).replace("<div class='page-break'></div>", "", 1) \
            + "<div class='page-break'></div>" + answers_html(w) + "</body></html>"
        (HTML_DIR / f"week{w['week']}_exam.html").write_text(h)

if __name__ == "__main__":
    build()
    print("weeks:", [w["week"] for w in weeks])
