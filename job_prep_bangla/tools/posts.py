#!/usr/bin/env python3
"""Split the month into one folder per post: images (HTML -> PNG via shots.js) + caption.txt.
usage: posts.py OUT_DIR"""
import json, html, os, re, shutil, sys
from pathlib import Path

SP = Path(__file__).parent
OUT = Path(sys.argv[1])
JOBS = SP / "postjobs"; shutil.rmtree(JOBS, ignore_errors=True); JOBS.mkdir()
BRAND = os.environ.get("BRAND", "নিয়োগ দরবার")
BD = str.maketrans("0123456789", "০১২৩৪৫৬৭৮৯")
bn = lambda n: str(n).translate(BD)
LBL = ["ক", "খ", "গ", "ঘ"]
e = lambda s: html.escape(str(s or ""))
LOGO_W = "file://" + str((SP.parent / "branding" / "logo_white_tight.png").resolve())
FONTS = (SP / "fonts" / "local.css").read_text().replace("url(", "url(file://" + str(SP / "fonts") + "/")
DAY_EN = {"শনিবার": "Sat", "রবিবার": "Sun", "সোমবার": "Mon", "মঙ্গলবার": "Tue", "বুধবার": "Wed", "বৃহস্পতিবার": "Thu", "শুক্রবার": "Fri"}
DAYS = list(DAY_EN)
DEFAULT_TAGS = "#বিসিএস_প্রস্তুতি #চাকরির_প্রস্তুতি #বাংলা_ব্যাকরণ #প্রাইমারি_নিয়োগ #ব্যাংক_জব"

CSS = FONTS + """
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { width: var(--w); height: var(--h); }
body { font-family: 'Hind Siliguri', sans-serif; color: #17213a; background: #f6f3ec; position: relative; overflow: hidden; }
.frame { position:absolute; inset: 0; display:flex; flex-direction:column; padding: 64px 70px 0; }
.top { display:flex; justify-content:space-between; align-items:center; }
.badge { background:#0f4c81; color:#fff; font-weight:700; font-size:34px; padding: 6px 26px 8px; border-radius: 40px; }
.badge.warn { background:#c0392b; } .badge.gold { background:#e8a33d; color:#17213a; }
.count { font-size: 32px; color:#2f3a52; font-weight:700; }
.fit { flex:1; display:flex; flex-direction:column; justify-content:center; overflow:hidden; padding: 20px 0; }
.content { font-size: 52px; line-height: 1.45; font-weight: 500; color: #0e1628; }
.h { font-weight: 700; color:#0f4c81; font-size: 1.25em; line-height: 1.25; margin-bottom: .45em; }
.cover .h { font-size: 1.7em; color:#17213a; }
.cover .sub { color:#0f4c81; font-weight:600; }
.bar { width: 120px; height: 12px; background:#e8a33d; border-radius: 6px; margin: .35em 0 .55em; }
.row { padding: .22em 0; border-bottom: 2px dashed #d8d2c4; display:flex; flex-wrap: wrap; column-gap: .4em; align-items: baseline; }
.row:last-child { border-bottom: 0; }
.row .l { font-weight:700; flex: 0 1 auto; }
.row .ar { color:#e8a33d; font-weight:700; }
.row .r { color:#0f4c81; font-weight:600; }
.line { padding: .12em 0; font-weight: 500; }
.ok { color:#16794c; font-weight:700; } .no { color:#c0392b; font-weight:700; }
.q { font-weight:700; line-height:1.35; margin-bottom:.6em; }
.src { display:inline-block; font-size:.58em; font-weight:600; color:#fff; background:#5b6475; border-radius: 8px; padding: .05em .5em .12em; margin-top:.4em; }
.opts { display:grid; grid-template-columns: 1fr 1fr; gap: .45em .6em; }
.opts.one { grid-template-columns: 1fr; }
.opt { font-weight:600; background:#fff; border: 3px solid #d9dee8; border-radius: 18px; padding: .25em .55em; display:flex; align-items:center; gap:.4em; }
.opt b { flex:none; display:inline-flex; width:1.35em; height:1.35em; border-radius:50%; background:#0f4c81; color:#fff; align-items:center; justify-content:center; font-size:.8em; }
.cta { margin-top:.7em; font-size:.74em; color:#2f3a52; font-weight:600; }
.exams { margin-top:.5em; }
.exams div { background:#fff; border-left: 10px solid #e8a33d; border-radius: 10px; padding: .15em .55em; margin: .22em 0; font-size: .82em; font-weight:600; }
.foot { height: 132px; display:flex; justify-content:space-between; align-items:center; border-top: 3px solid #0f4c81; margin: 0 -70px; padding: 0 70px; background:#0f4c81; color:#fff; font-size: 30px; font-weight:600; }
.foot .s { color:#f3d29b; }
.big { font-size: 1.5em; font-weight:700; color:#0f4c81; text-align:center; line-height:1.3; }
.center { text-align:center; }
"""

FIT_JS = """
<script>
document.fonts.ready.then(() => {
  const box = document.querySelector('.fit'), c = document.querySelector('.content');
  const fits = (s) => { c.style.fontSize = s + 'px'; return c.scrollHeight <= box.clientHeight - 60 && c.scrollWidth <= box.clientWidth + 2; };
  let lo = 22, hi = parseFloat(document.body.dataset.max || 80);
  while (hi - lo > 1) { const m = Math.floor((lo + hi) / 2); if (fits(m)) lo = m; else hi = m; }
  if (fits(hi)) lo = hi; fits(lo);
  document.body.dataset.ready = '1';
});
</script>"""

jobs = []
def page(path, inner, badge, badge_cls="", count="", foot_right="", w=1080, h=1350, cls="", mx=None):
    mx = mx or (110 if h > 1500 else 76)
    doc = (f"<!doctype html><html lang='bn'><head><meta charset='utf-8'><style>:root{{--w:{w}px;--h:{h}px}}{CSS}</style></head>"
           f"<body data-max='{mx}'><div class='frame'><div class='top'><span class='badge {badge_cls}'>{e(badge)}</span><span class='count'>{e(count)}</span></div>"
           f"<div class='fit'><div class='content {cls}'>{inner}</div></div>"
           f"<div class='foot'><img src='{LOGO_W}' style='height:108px;display:block'><span class='s'>{e(foot_right)}</span></div></div>{FIT_JS}</body></html>")
    hp = JOBS / (f"j{len(jobs):04d}.html"); hp.write_text(doc)
    jobs.append({"html": str(hp), "png": str(path), "w": w, "h": h})

def fmt_line(t):
    t = e(t).replace("✔", "<span class='ok'>✔</span>").replace("✘", "<span class='no'>✘</span>")
    for sep in ("→", "↔", " = "):
        if sep in t and t.count(sep) == 1 and len(t) < 110:
            l, r = t.split(sep)
            return f"<div class='row'><span class='l'>{l.strip()}</span><span class='ar'>{sep.strip()}</span><span class='r'>{r.strip()}</span></div>"
    return f"<div class='line'>{t}</div>"

def slide_inner(text, cover=False):
    lines = [l for l in str(text).split("\n") if l.strip()]
    head, rest = lines[0], lines[1:]
    if cover:
        return f"<div class='h'>{e(head)}</div><div class='bar'></div>" + "".join(f"<div class='sub'>{e(l)}</div>" for l in rest)
    return f"<div class='h'>{e(head)}</div>" + "".join(fmt_line(l) for l in rest)

def mcq_inner(m, cta="সঠিক উত্তর কমেন্টে লিখুন: ক / খ / গ / ঘ"):
    q = m["q"].split(" / ")[0]
    one = max(len(o) for o in m["opts"]) > 10
    opts = "".join(f"<div class='opt'><b>{LBL[i]}</b><span>{e(o)}</span></div>" for i, o in enumerate(m["opts"]))
    src = f"<div><span class='src'>{e(m['src'])}</span></div>" if m.get("src") else ""
    return f"<div class='q'>{e(q)}{src}</div><div class='opts {'one' if one else ''}'>{opts}</div><div class='cta'>{e(cta)}</div>"

def mcq_plain(m):
    q = m["q"].split(" / ")[0]
    src = f" [{m['src']}]" if m.get("src") else ""
    return f"{q}{src}\n" + "\n".join(f"{LBL[i]}) {o}" for i, o in enumerate(m["opts"]))

def write_caption(folder, caption, hashtags, comment=None, extra=None):
    parts = [caption.strip(), "", hashtags or DEFAULT_TAGS]
    if extra: parts += ["", extra]
    if comment:
        parts += ["", "━━━━━━━━━━━━━━━━", "📌 প্রথম কমেন্টে দিন (পোস্টের ২–৩ ঘণ্টা পর):", "━━━━━━━━━━━━━━━━", comment.strip()]
    (folder / "caption.txt").write_text("\n".join(parts) + "\n")

summary = []
for wp in sorted((SP / "weeks").glob("week*.json")):
    w = json.load(open(wp)); W = w["week"]
    wdir = OUT / f"week{W}"; shutil.rmtree(wdir, ignore_errors=True); wdir.mkdir(parents=True)
    daily = {d["day"]: d for d in w.get("daily_mcq", [])}
    posts = {p["day"]: p for p in w["posts"]}
    tags = next((p.get("hashtags") for p in w["posts"] if p.get("hashtags")), DEFAULT_TAGS)
    for di, day in enumerate(DAYS, 1):
        tag = f"মাস ১ · সপ্তাহ {bn(W)} · দিন {bn(di)}"
        # morning MCQ
        if day in daily:
            d = daily[day]
            f = wdir / f"D{di}_{DAY_EN[day]}_1_Morning_DinerProshno"; f.mkdir()
            page(f / "post.png", mcq_inner(d), "দিনের প্রশ্ন", foot_right=tag)
            write_caption(f, "📌 দিনের প্রশ্ন\n\n" + mcq_plain(d) + "\n\nউত্তর জানলে কমেন্টে লিখুন 👇\nসঠিক উত্তর ও ব্যাখ্যা দেওয়া হবে কমেন্টে।", tags, d.get("comment"))
            summary.append((W, day, "সকাল", "দিনের প্রশ্ন", f.name))
        if day not in posts: continue
        p = posts[day]; fmt = p["format"]
        f = wdir / f"D{di}_{DAY_EN[day]}_2_Night_{re.sub(r'[^A-Za-z]', '', {'ক্যারোসেল':'Carousel','রিল':'Reel','ফাঁদ প্রশ্ন':'TrapQuestion','৫ প্রশ্ন':'FiveMCQ','বারবার আসা প্রশ্ন':'RepeatedQuestion','সাপ্তাহিক পরীক্ষা':'WeeklyExam'}.get(fmt,'Post'))}"
        f.mkdir()
        extra = None
        if p.get("slides"):
            n = len(p["slides"])
            for i, s in enumerate(p["slides"], 1):
                page(f / f"slide{i:02d}.png", slide_inner(s, cover=(i == 1)), "গুলিয়ে ফেলবেন না" if day == "শনিবার" else "চিনে নিন",
                     "gold" if i == 1 else "", f"{bn(i)}/{bn(n)}", tag, cls="cover" if i == 1 else "")
        elif p.get("script"):
            sc = p["script"]; n = len(sc)
            for i, s in enumerate(sc, 1):
                s2 = re.sub(r"^\s*(?:[০-৯]+\.|হুক|Hook|HOOK|CTA|সিটিএ|শেষে|ক্লোজিং)\s*[:।.-]?\s*", "", s)
                inner = f"<div class='big'>{e(s2)}</div>" if i in (1, n) else slide_inner(s2.replace(" — ", "\n", 1)) if " — " in s2 else fmt_line(s2)
                page(f / f"frame{i:02d}.png", inner, "১ মিনিটে ১০টা", "gold", f"{bn(i)}/{bn(n)}", tag, w=1080, h=1920)
            (f / "reel_script.txt").write_text("রিল স্ক্রিপ্ট (প্রতি ফ্রেম ৪–৫ সেকেন্ড; CapCut-এ frame ছবিগুলো পরপর বসিয়ে ভয়েস দিন)\n\n" +
                                                "\n".join(f"ফ্রেম {bn(i)}: {s}" for i, s in enumerate(sc, 1)) + "\n")
        elif p.get("mcqs"):
            ms = p["mcqs"]; n = len(ms) + 1
            page(f / "slide01.png", slide_inner(p["title"] + "\nসোয়াইপ করুন, উত্তর মিলিয়ে নিন কমেন্টে", cover=True), "৫ প্রশ্ন", "gold", f"১/{bn(n)}", tag, cls="cover")
            for i, m in enumerate(ms, 2):
                page(f / f"slide{i:02d}.png", mcq_inner(m, "উত্তর লিখে রাখুন, মিলিয়ে নিন কমেন্টে"), f"প্রশ্ন {bn(i-1)}", "", f"{bn(i)}/{bn(n)}", tag)
            extra = "সঠিক উত্তর: " + ", ".join(f"{bn(i)}-{LBL[m['ans']]}" for i, m in enumerate(ms, 1))
        elif p.get("mcq"):
            page(f / "post.png", mcq_inner(p["mcq"], "প্রশ্নটা আরেকবার পড়ুন, তারপর কমেন্টে উত্তর দিন"), "ফাঁদ প্রশ্ন ⚠", "warn", "", tag)
        elif p.get("exams"):
            lines = [l for l in (p.get("design_text") or p["title"]).split("\n") if l.strip()]
            body = [l for l in lines[1:] if not l.startswith("এসেছে")]
            inner = (f"<div class='h'>{e(body[0] if body else p['title'])}</div>" + "".join(f"<div class='line'>{e(l)}</div>" for l in body[1:]) +
                     f"<div class='cta'>যেসব পরীক্ষায় এসেছে ({bn(len(p['exams']))}টি):</div><div class='exams'>" + "".join(f"<div>{e(x)}</div>" for x in p["exams"]) + "</div>")
            page(f / "post.png", inner, "বারবার আসা প্রশ্ন", "gold", "", tag)
        else:  # weekly exam announcement
            t = w["topics"]
            inner = (f"<div class='h'>সাপ্তাহিক পরীক্ষা {bn(W)}</div><div class='bar'></div>"
                     f"<div class='line'>📘 {e(t['grammar'])}</div><div class='line'>📗 {e(t['vocab'])}</div><div class='line'>📕 {e(t['literature'])}</div>"
                     f"<div class='cta'>২৫টি প্রশ্ন · ১৫ মিনিট · প্রতি ভুলে ০.৫০ কাটা<br>প্রশ্ন + ব্যাখ্যাসহ উত্তরের PDF কমেন্টে</div>")
            page(f / "post.png", inner, "পরীক্ষা", "warn", "", tag, cls="cover")
            src = OUT.parent / f"Week{W}_Exam_with_Answers.pdf"
            if src.exists(): shutil.copy(src, f / src.name)
        write_caption(f, p.get("caption", ""), p.get("hashtags"), p.get("answer_comment"), extra)
        summary.append((W, day, "রাত", fmt, f.name))

(SP / "postjobs.json").write_text(json.dumps(jobs))
with open(OUT / "INDEX.txt", "w") as fh:
    fh.write("পোস্টের সূচি: প্রতিটি ফোল্ডারে ছবি (post.png / slideNN.png / frameNN.png) আর caption.txt আছে।\n"
             "সময়: সকালের পোস্ট ৭–৯টা, রাতের পোস্ট ৮–১১টা। উত্তরের কমেন্ট ২–৩ ঘণ্টা পরে।\n\n")
    for W, day, when, fmt, name in summary:
        fh.write(f"সপ্তাহ {bn(W)} | {day:<11} | {when} | {fmt:<16} | week{W}/{name}\n")
print(len(jobs), "images,", len(summary), "posts")
