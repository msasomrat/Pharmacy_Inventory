# Brief: compose the CAAB crash-series content (posts + 2 model tests + suggestion notes)

## Context
A Bangladeshi govt-job-prep Facebook page runs a CAAB (বেসামরিক বিমান চলাচল কর্তৃপক্ষ) crash series.
CAAB MCQ exams: **Senior Officer on Fri 27 Nov 2026, 3 pm**; **18 other posts on Fri 4 Dec 2026, 3 pm**
(Medical Officer, Procurement Officer, Asst Maintenance Engineer, Asst Programmer, Aerodrome Officer (ATM),
Senior Cartographer, CNS Engineer, Air Transportation Officer, Inspector (Ops), Security Officer, Airworthiness
Inspectors, Economist, Fire Officer, Accounts Officer, Audit Officer, Asst Engineer Civil & E/M).
Today is Wed 18 Nov 2026 (the exam-date post goes out today; you start from Thu 19 Nov).

Source material — two verified question banks (read both fully):
- /tmp/claude-0/-home-user-Pharmacy-Inventory/fb6e0f22-3e58-53e8-8d2f-dd4d414f36cb/scratchpad/caab/bank1.json
- /tmp/claude-0/-home-user-Pharmacy-Inventory/fb6e0f22-3e58-53e8-8d2f-dd4d414f36cb/scratchpad/caab/bank2.json
Each has gk_facts, mcqs (with src, why, more) and flags. Respect the flags: never use an item a flag calls
wrong/doubtful/outdated; avoid facts marked time_sensitive unless you are sure they are current (no fleet counts,
no "current" office-holders, no rankings).

## Hard rules
- The page name must NOT appear as text anywhere (no "নিয়োগ দরবার", no #নিয়োগ_দরবার). Say "আমাদের পেজ" if needed.
- Bangla digits (০-৯) in Bangla text. MCQ options: 4 strings, no ক./a) prefix; `ans` index 0–3; keep `src` exactly as in the bank.
- Image text must be SHORT and readable on a phone: a slide = 1 heading line + at most 5 lines, each line ≤ 40 characters.
  Pairs read best as "বাম → ডান" or "বাম = ডান" (exactly one arrow/equals per line).
- Captions: friendly, casual Facebook Bangla (not stiff/professional), hook first line, short lines, 1–3 emoji,
  CTA (সেভ করুন / কমেন্টে উত্তর দিন / বন্ধুকে ট্যাগ করুন). Mention the exam countdown naturally.
  `answer_comment` for every post that asks a question: "✅ উত্তর: গ. ..." + 1–3 lines of explanation with extra facts.
- Spread items: don't reuse the same MCQ across posts; the model tests may reuse at most 5 posted MCQs.
- Every fact must be correct. If unsure, leave it out.

## Calendar (fill exactly; times are Bangladesh time)
countdown text per day: until 26 Nov "সিনিয়র অফিসার পরীক্ষার আর N দিন" (N = days to 27 Nov); 27 Nov "আজ সিনিয়র অফিসার পরীক্ষা";
28 Nov–3 Dec "৪ ডিসেম্বরের পরীক্ষার আর N দিন"; 4 Dec "আজ ১৮টি পদের পরীক্ষা".
Every day has a morning post (slot "সকাল", time "৮:০০") and a night post (slot "রাত", time "৯:০০"), except as noted.
- Morning: format "দিনের প্রশ্ন" (one aviation/CAAB/Biman MCQ preferably with a Biman/CAAB exam tag) — except 27 Nov and
  4 Dec mornings: format "বার্তা" (badge "শুভকামনা": short good-luck + exam-day checklist: রঙিন প্রবেশপত্র, কলম, সময়ের আগে কেন্দ্রে).
- Night:
  19 Nov ক্যারোসেল: বিমান বাংলাদেশ এয়ারলাইন্স (ইতিহাস ও মূল তথ্য)
  20 Nov ৫ প্রশ্ন: বিগত বিমান পরীক্ষার ৫ প্রশ্ন (mixed subjects)
  21 Nov ক্যারোসেল: CAAB (প্রতিষ্ঠা, কাজ, সদর দপ্তর, ICAO সম্পর্ক)
  22 Nov ফাঁদ প্রশ্ন
  23 Nov বারবার আসা প্রশ্ন (a fact asked in more than one Biman/CAAB paper; list those papers in the slide/caption only if the banks show it; otherwise a high-frequency aviation fact framed as "প্রায় প্রতিটি বিমান পরীক্ষায় আসে" ONLY if that is true from the banks — else pick another verified repeated item)
  24 Nov মডেল টেস্ট (test_id 1)
  25 Nov ক্যারোসেল: বাংলাদেশের বিমানবন্দর ও কোড
  26 Nov ক্যারোসেল: "পরীক্ষার আগের রাতের ২০ তথ্য" (4–5 slides, 4–5 facts each)
  27 Nov night: format "বার্তা", time "৬:০০" (সন্ধ্যা), badge "আপনার মতামত": "পরীক্ষা কেমন হলো?" — ask candidates to comment which questions came
  28 Nov ক্যারোসেল: ICAO, IATA ও বিভিন্ন দেশের এয়ারলাইন্স
  29 Nov ৫ প্রশ্ন: গণিতের শর্টকাট (badge "গণিত") — answer_comment shows 1-line shortcuts
  30 Nov ফাঁদ প্রশ্ন
  1 Dec মডেল টেস্ট (test_id 2)
  2 Dec ক্যারোসেল: এভিয়েশন পরিভাষা ও মাপ (নটিক্যাল মাইল, নট, ATC ইত্যাদি)
  3 Dec ক্যারোসেল: "পরীক্ষার আগের রাতের ২০ তথ্য (পর্ব ২)" — different facts from 26 Nov
  4 Dec night: "বার্তা", time "৬:০০", badge "আপনার মতামত": পরীক্ষা কেমন হলো + thanks + "সামনে আরও সরকারি চাকরির প্রস্তুতি চলবে"
For "বার্তা" posts `slides` holds one string: first line = big headline (≤ 22 chars), next 1–3 short lines.
For ক্যারোসেল: slide 1 = cover (headline + 1–2 short lines), then 3–5 content slides. Give "badge" (e.g. "চিনে নিন", "বিমান", "CAAB", "আগের রাতের রিভিশন").

## Model tests
Two tests, 30 questions each, `minutes` 30, ordered by subject group: aviation 8, gk 6, bangla 5, english 5, math 4, ict 2.
`topic` = subject key (aviation|gk|bangla|english|math|ict). Each question has `why` (1 line) and `more` (1–3 related facts).
Test 1 title "মডেল টেস্ট ১: সিনিয়র অফিসার স্পেশাল", date 2026-11-24. Test 2 title "মডেল টেস্ট ২: ৪ ডিসেম্বরের ১৮ পদ স্পেশাল", date 2026-12-01.
No question repeated between the two tests. Correct answers spread across ক/খ/গ/ঘ (rotate options if needed — then recheck `ans`!).

## Suggestion notes
`suggestion_notes`: 5–7 sections for a "CAAB সাজেশন" PDF: বিমান বাংলাদেশ এয়ারলাইন্স, CAAB, বিমানবন্দর ও কোড, ICAO/IATA ও আন্তর্জাতিক সংস্থা,
বিভিন্ন দেশের এয়ারলাইন্স (table), এভিয়েশন পরিভাষা ও মাপ (table), বিগত পরীক্ষায় বারবার আসা অন্যান্য তথ্য. 45–80 bullets total, dense, one fact per bullet.
Tables: list of rows, first row header, 2 columns.

## Output
Write UTF-8 JSON to /home/user/Pharmacy_Inventory/job_prep_bangla/caab/caab_series.json and validate with json.load. Schema:
{
 "days": [ {"date": "2026-11-19", "label": "১৯ নভেম্বর, বৃহস্পতিবার", "countdown": "...",
   "posts": [
     {"slot": "সকাল", "time": "৮:০০", "format": "দিনের প্রশ্ন", "mcq": {"q":"","opts":["","","",""],"ans":0,"src":""}, "caption": "...", "answer_comment": "...", "hashtags": "..."},
     {"slot": "রাত", "time": "৯:০০", "format": "ক্যারোসেল", "badge": "বিমান", "title": "...", "slides": ["heading\\nline\\nline", "..."], "caption": "...", "hashtags": "..."},
     {"format": "৫ প্রশ্ন", "badge": "...", "title": "...", "mcqs": [5 mcq objects], "caption": "...", "answer_comment": "..."},
     {"format": "ফাঁদ প্রশ্ন", "mcq": {...}, "caption": "...", "answer_comment": "..."},
     {"format": "বারবার আসা প্রশ্ন", "badge": "বারবার আসা প্রশ্ন", "slides": ["..."], "caption": "...", "answer_comment": "..."},
     {"format": "মডেল টেস্ট", "test_id": 1, "caption": "...", "answer_comment": "..."},
     {"format": "বার্তা", "badge": "শুভকামনা", "slides": ["headline\\nline"], "caption": "..."}
   ]} ],
 "tests": [ {"id": 1, "title": "...", "date": "2026-11-24", "minutes": 30, "questions": [ {"topic":"aviation","q":"","opts":[],"ans":0,"src":"","why":"","more":[]} ]} ],
 "suggestion_notes": [ {"heading": "...", "bullets": ["..."], "table": [["বাম","ডান"],["..",".."]]} ],
 "flags": ["anything you left out or changed and why"]
}
Hashtags default: "#CAAB #বেবিচক #বিমান_নিয়োগ #চাকরির_প্রস্তুতি #সরকারি_চাকরি" (+1–2 topical).
Self-check before finishing (write a small script): 16 days (19 Nov–4 Dec), each test exactly 30 with the subject counts,
all ans in 0–3, no latin digits in Bangla text, no "নিয়োগ দরবার" anywhere, every slide line ≤ 40 chars, ≤ 6 lines per slide.
Reply with a short summary: counts, answer distribution of each test, and the flags.
