# Brief: one week of Bangla job-prep content (Facebook page + weekly exam)

## Context
A teacher runs a Bangladeshi govt-job-prep Facebook page (BCS, bank, primary teacher, NTRCA etc.).
Source: the scanned book "Crack Previous MCQ" (Bangla section). Every MCQ in it has the exam it came
from printed after the question in brackets, e.g. [৩২তম বিসিএস], [সোনালী ব্যাংকের সিনিয়র অফিসার: ১৮],
and "উত্তর: ক/খ/গ/ঘ" at the right. Some have a ব্যাখ্যা paragraph.

The PDFs are image scans (pdftotext returns nothing) — read them with the Read tool, `pages` = ONE page or ONE range
(e.g. "5-9"; max 20). Files (all in /root/.claude/uploads/fb6e0f22-3e58-53e8-8d2f-dd4d414f36cb/):
- P1 = cea6ac8c-Crack_Bangla_Part1_Bhasha_p1-90.pdf      book page ≈ pdf page − 4
- P2 = 00dcc4b1-Crack_Bangla_Part2_Bhasha_p91-175.pdf    book page ≈ pdf page + 86
- P3 = 4d138512-Crack_Bangla_Part3_Bhasha_p176-259.pdf   book page ≈ pdf page + 170
- P4 = b95a28c6-Crack_Bangla_Part4_Sahitya_p260-358.pdf  book page ≈ pdf page + 254
(The printed page number is at the bottom of every page; offsets may drift ±2 — check and adjust.)

## Goal
Students should learn the MOST from the FEWEST MCQs. So:
- Pick high-yield questions: BCS ones and questions that recur across several exams first.
- Every explanation must be information-dense: why the answer is right in one line, then 1–3 closely
  related facts that are themselves likely exam questions (the "other side" of the question, sibling facts,
  why the trap option is wrong). Short, crisp Bangla. No filler.

## Hard rules
1. Transcribe questions, options and source tags EXACTLY as printed (careful with যুক্তাক্ষর and spelling).
   Never invent or guess a source tag; if none is printed, use "".
2. Keep the book's answer unless it is clearly wrong. If a fact is outdated or disputed
   (e.g. number of languages in the world), either skip the question or keep it and give the current fact in
   "more" (e.g. "পরীক্ষার অপশন অনুযায়ী উত্তর ঘ; তবে বর্তমান হিসাবে ...").
   List every book error / doubtful key you found in "flags".
3. Write explanations in your own words — never copy the book's ব্যাখ্যা paragraphs verbatim.
4. Bangla digits (০-৯) everywhere in Bangla text. Options are 4 strings WITHOUT the "ক." prefix.
5. Do not use the word "Crack" or the book/publisher name anywhere in the output.
6. The weekly exam must test the week's content: at least 15 of its 25 questions should test facts that appear in
   this week's posts or notes (reusing up to 8 of the week's posted MCQs is fine — it reinforces), the rest new
   questions from the same topics. Mix: ~11 from the grammar topic, ~7 vocab topic, ~7 literature topic.
   Order the exam by topic. Make sure the correct answers are spread across ক/খ/গ/ঘ.

## Weekly posting plan (fill every slot)
- শনিবার  "গুলিয়ে ফেলবেন না" carousel on the grammar topic: 4–6 slides of easily-confused facts.
- রবিবার  Reel script "১ মিনিটে ১০টা" on the vocab topic: hook line, 10 items, closing CTA.
- সোমবার  ফাঁদ প্রশ্ন: one tricky MCQ (negation, near-identical options…) + answer comment explaining the trap.
- মঙ্গলবার  সাহিত্য post on the literature topic: "চিনে নিন" table/carousel (e.g. work → author, character → book).
- বুধবার  "প্রাইমারি/ব্যাংকে আসা ৫ প্রশ্ন": 5 MCQs whose tags are primary-school or bank exams.
- বৃহস্পতিবার "বারবার আসা প্রশ্ন": a fact asked in several different exams — list the exams exactly as printed
  (only exams the book actually shows; the same question often appears with "/" alternative wordings and several tags,
  or repeats under different numbers).
- শুক্রবার  announcement caption for the weekly exam (the exam itself goes in "exam").
- Plus 6 morning "দিনের প্রশ্ন" MCQs (শনি–বৃহস্পতি), each with an answer-comment text.

Post captions: natural Facebook Bangla, a hook first line, short lines, 1–3 emoji max, end with a CTA
(সেভ করুন / কমেন্টে উত্তর দিন), then 4–6 hashtags (#বিসিএস_প্রস্তুতি #চাকরির_প্রস্তুতি #বাংলা_ব্যাকরণ etc.).
"design_text" is the text that goes ON the image/slides (short!). For carousels use "slides": [..].

## Output
Write valid UTF-8 JSON (ensure_ascii False) to the path given in your task, then validate it with
`python3 -c "import json;json.load(open(PATH))"`. Schema:

{
  "week": 1,
  "title": "সপ্তাহ ১: ...",                       // short
  "topics": {"grammar": "...", "vocab": "...", "literature": "..."},
  "notes": [                                       // dense revision notes for the student PDF
    {"heading": "...", "bullets": ["..."], "table": [["বাম", "ডান"], ...]}   // table optional, first row = header
  ],                                               // 3–5 sections, 25–45 bullets total, + tables where useful
  "daily_mcq": [ {"day": "শনিবার", "q": "...", "opts": ["","","",""], "ans": 0, "src": "...", "comment": "..."} ],  // 6
  "posts": [
    {"day": "শনিবার", "format": "ক্যারোসেল", "title": "...", "slides": ["..."], "caption": "...", "hashtags": "..."},
    {"day": "রবিবার", "format": "রিল", "title": "...", "script": ["hook", "item 1", "...", "CTA"], "caption": "...", "hashtags": "..."},
    {"day": "সোমবার", "format": "ফাঁদ প্রশ্ন", "title": "...", "mcq": {"q":"","opts":[],"ans":0,"src":""}, "design_text": "...", "caption": "...", "answer_comment": "...", "hashtags": "..."},
    {"day": "মঙ্গলবার", "format": "ক্যারোসেল", "title": "...", "slides": ["..."], "caption": "...", "hashtags": "..."},
    {"day": "বুধবার", "format": "৫ প্রশ্ন", "title": "...", "mcqs": [{"q":"","opts":[],"ans":0,"src":""}], "caption": "...", "answer_comment": "...", "hashtags": "..."},
    {"day": "বৃহস্পতিবার", "format": "বারবার আসা প্রশ্ন", "title": "...", "design_text": "...", "exams": ["..."], "caption": "...", "hashtags": "..."},
    {"day": "শুক্রবার", "format": "সাপ্তাহিক পরীক্ষা", "title": "...", "caption": "...", "hashtags": "..."}
  ],
  "exam": [  // exactly 25
    {"topic": "grammar|vocab|literature", "q": "...", "opts": ["","","",""], "ans": 0, "src": "...",
     "why": "one line: why this is the answer",
     "more": ["related high-yield fact", "..."]}       // 1–3 items
  ],
  "flags": ["book page N, Q#: issue ..."]
}

When done, reply with a 5-line summary: file path, counts (notes bullets, exam size), the answer
distribution of the exam (ক/খ/গ/ঘ counts), and the flags.
