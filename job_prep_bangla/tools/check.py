#!/usr/bin/env python3
import json, sys, re
from pathlib import Path
from collections import Counter
W = Path(__file__).parent / "weeks"
LBL = "কখগঘ"
allq = {}
for p in sorted(W.glob("week*.json")):
    w = json.load(open(p)); errs = []
    ex = w.get("exam", [])
    if len(ex) != 25: errs.append(f"exam size {len(ex)}")
    for i, q in enumerate(ex, 1):
        if len(q.get("opts", [])) != 4: errs.append(f"Q{i} opts {len(q.get('opts', []))}")
        if q.get("ans") not in (0, 1, 2, 3): errs.append(f"Q{i} ans {q.get('ans')}")
        if q.get("topic") not in ("grammar", "vocab", "literature"): errs.append(f"Q{i} topic {q.get('topic')}")
        if not q.get("why"): errs.append(f"Q{i} no why")
        if len(set(q.get("opts", []))) != len(q.get("opts", [])): errs.append(f"Q{i} duplicate opts")
        if re.search(r"[0-9]", q["q"] + "".join(q["opts"])): errs.append(f"Q{i} latin digit")
        if any(re.match(r"^[কখগঘ][.)]", o) for o in q["opts"]): errs.append(f"Q{i} opt prefix")
        key = re.sub(r"\W", "", q["q"])[:40]
        if key in allq: errs.append(f"Q{i} duplicate of {allq[key]}")
        allq[key] = f"w{w['week']}Q{i}"
    order = [q["topic"] for q in ex]
    if order != sorted(order, key=lambda t: order.index(t)): errs.append("topics not grouped")
    days = [x["day"] for x in w.get("posts", [])]
    dist = Counter(LBL[q["ans"]] for q in ex if q.get("ans") in (0,1,2,3))
    nb = sum(len(n.get("bullets", [])) for n in w.get("notes", []))
    tc = Counter(q.get("topic") for q in ex)
    print(f"week{w['week']}: exam={len(ex)} dist={dict(dist)} topics={dict(tc)} notes={len(w['notes'])}/{nb} bullets daily={len(w.get('daily_mcq', []))} posts={days}")
    print("  flags:", len(w.get("flags", [])), "| errors:", errs or "none")
    if "Crack" in json.dumps(w, ensure_ascii=False) or "ক্র্যাক" in json.dumps(w, ensure_ascii=False): print("  !! brand word present")
