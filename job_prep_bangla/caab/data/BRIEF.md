# Brief: extract a high-yield question bank for the CAAB (বেসামরিক বিমান চলাচল কর্তৃপক্ষ) MCQ exams

## Why
A Bangladeshi govt-job-prep Facebook page ("নিয়োগ দরবার") is running a crash series for the CAAB recruitment
MCQ exams: Senior Officer on 27 Nov 2026, and 18 other posts (Aerodrome Officer, Assistant Programmer,
Security Officer, Accounts Officer, Assistant Engineer etc.) on 4 Dec 2026. Today is 18 Nov 2026.
Your bank will be turned into daily posts, two 30-question model tests and a suggestion PDF.

## Source
Scanned PDF (image only; pdftotext gives nothing). Read with the Read tool, `pages` = ONE page or ONE range, max 20 per call.
It is a compilation: Biman/CAAB/aviation general-knowledge notes, then past Biman Bangladesh Airlines / CAAB
exam question papers with solutions (Bangla, English, math, GK, written questions). Watermarks "Job Hunter",
"Recent Publications", "Matrix BCS Series" are just publisher marks.

## What to extract
1. `gk_facts`: aviation-specific facts likely to be asked — Biman history, fleet, routes/offices, CAAB history &
   functions, airports of Bangladesh (names, locations, codes), ICAO/IATA, airlines of countries, aviation terms
   (nautical mile, ATC, etc.). 50–90 facts, one crisp Bangla sentence each. Mark `time_sensitive: true` for
   anything that changes over time (fleet size, rankings, "current" chairman/CEO, "best airline 2024" etc.).
2. `mcqs`: the best past-exam MCQs, prioritising (a) aviation/CAAB/Biman-specific, (b) questions whose source tag
   names a CAAB or Biman exam, (c) classic recurring Bangla/English/math/GK. 70–110 items.
   - Transcribe question/options exactly (fix only obvious OCR-like misprints, and list them in flags).
   - Copy the exam/source tag exactly as printed if there is one (e.g. "বিমান বাংলাদেশ এয়ারলাইন্স (জুনিয়র অফিসার) ২০২৩");
     if a whole paper has a heading naming the exam, use that heading for its questions. Never invent a tag; else "".
   - VERIFY every answer yourself, especially math (the book has errors — e.g. a circle circumference:diameter item
     keyed to an option that does not match its own solution). If the book key is wrong, give the correct answer and
     flag it. Drop items with no correct option.
   - `why`: one line why the answer is right; `more`: 1–3 related high-yield facts (the student should learn several
     facts from one MCQ). For math, `why` is the shortest solution method / shortcut.
3. `flags`: book errors, outdated facts, unreadable items.

Bangla digits (০-৯) in Bangla text; options are 4 strings without "ক."/"a)" prefixes; `ans` is index 0–3.
Write explanations in your own words (don't copy book solution paragraphs). Don't mention the publishers.

## Output
Write UTF-8 JSON to the path in your task and validate with `python3 -c "import json;json.load(open(PATH))"`:
{
 "part": 1,
 "pages_read": "1-59",
 "contents": ["short list of sections/papers found, with pdf page ranges"],
 "gk_facts": [{"topic": "বিমান|CAAB|বিমানবন্দর|এয়ারলাইন্স|সংস্থা|পরিভাষা|অন্যান্য", "fact": "...", "page": 3, "time_sensitive": false}],
 "mcqs": [{"subject": "aviation|gk|bangla|english|math|ict", "q": "...", "opts": ["","","",""], "ans": 0,
           "src": "...", "why": "...", "more": ["..."], "page": 12}],
 "flags": ["pdf p.N: ..."]
}
Reply with a 5-line summary: path, counts by subject, number of tagged CAAB/Biman items, main flags.
