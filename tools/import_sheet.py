#!/usr/bin/env python3
"""Import the coach's weekly programming spreadsheet into structured JSON.

Usage:
    python3 tools/import_sheet.py INPUT.xlsx --out-dir OUTPUT_DIR [--today YYYY-MM-DD]

Privacy: the input workbook and every output file contain personal training
data. Keep them out of version control (the repo .gitignore excludes *.xlsx
and data/). Nothing is uploaded anywhere; the script only reads INPUT and
writes into OUTPUT_DIR.

Outputs (in --out-dir):
    history.json        list of workouts sorted by date
    movements.json      normalized movement names with counts / section kinds
    import_report.md    coverage stats, six-lift history, unparsed patterns

Design notes
- Each tab is one week. Row 1 holds day names (column positions can drift, so
  columns are located by header text), row 2 holds dates, column A holds the
  section labels. "Coaches Comments" / "Athlete Comments" rows belong to the
  section label above them. The optional "COMMENTS" column holds a weekly note
  per section; it is attached to every section of that kind as `week_note`.
- The parser is defensive: `raw` is always kept and fields are left null/absent
  when a pattern is not recognized.
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import json
import os
import re
import sys

try:
    import openpyxl
except ImportError:  # pragma: no cover
    sys.exit("openpyxl is required: pip install openpyxl")


DAY_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
DAY_ABBR = {d: d[:3] for d in DAY_NAMES}
SECTION_LABELS = {
    "warm up": "warmup",
    "strength / skill": "strength",
    "metabolic conditioning": "metabolic",
    "accessory": "accessory",
}
EMPTY_BARBELL_LB = 45
KG_TO_LB = 2.20462

SIX_LIFTS = ["Deadlift", "Hang Power Clean", "Front Squat", "Back Squat", "Push Press", "Push Jerk"]


# --------------------------------------------------------------------------
# Cell helpers
# --------------------------------------------------------------------------

def cell_text(v):
    """Convert a cell value to text. Excel auto-converted some athlete scores
    such as "19:28" into times (19h28m); those are treated as mm:ss."""
    if v is None:
        return None
    if isinstance(v, dt.datetime):
        return v.strftime("%Y-%m-%d")
    if isinstance(v, dt.time):
        # Excel read "19:28" as 19:28:00 (h:m:s); athlete meant 19 min 28 sec.
        mm = v.hour
        ss = v.minute
        return f"{mm}:{ss:02d}"
    if isinstance(v, dt.timedelta):
        total_min = int(v.total_seconds() // 3600)  # hours were really minutes
        ss = int((v.total_seconds() % 3600) // 60)
        return f"{total_min}:{ss:02d}"
    if isinstance(v, float):
        if v.is_integer():
            return str(int(v))
        return repr(v)
    s = str(v).replace(" ", " ").strip()
    return s or None


def norm_ws(s):
    return re.sub(r"\s+", " ", s).strip()


# --------------------------------------------------------------------------
# Dates
# --------------------------------------------------------------------------

def tab_monday(tab, prev_monday, sheet_monday):
    """Derive the Monday date from a tab name like 'Week 12 (729)'.

    The parenthesized number is month+day without separators, so '105' could be
    1/05 or 10/5. We pick the candidate that is a Monday and closest after the
    previous week's Monday (or closest to the sheet's own date for the first tab).
    """
    m = re.search(r"\((\d{2,4})\)", tab)
    if not m:
        return None
    digits = m.group(1)
    anchor = (prev_monday + dt.timedelta(days=7)) if prev_monday else sheet_monday
    if anchor is None:
        return None
    cands = []
    for split in range(1, len(digits)):
        mo, da = int(digits[:split]), int(digits[split:])
        for yr in (anchor.year - 1, anchor.year, anchor.year + 1):
            try:
                d = dt.date(yr, mo, da)
            except ValueError:
                continue
            cands.append(d)
    if not cands:
        return None
    mondays = [d for d in cands if d.weekday() == 0] or cands
    if prev_monday:
        after = [d for d in mondays if d > prev_monday]
        mondays = after or mondays
    return min(mondays, key=lambda d: abs((d - anchor).days))


def parse_sheet_date(v, year_hint):
    """Row-2 date cell -> (date|None, note|None). Strings like '6/5 - ZOOM '."""
    if isinstance(v, dt.datetime):
        return v.date(), None
    if isinstance(v, dt.date):
        return v, None
    if v is None:
        return None, None
    s = str(v).strip()
    m = re.match(r"^(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\s*[-–:]?\s*(.*)$", s)
    if not m:
        return None, s or None
    mo, da = int(m.group(1)), int(m.group(2))
    yr = int(m.group(3)) if m.group(3) else year_hint
    if yr and yr < 100:
        yr += 2000
    try:
        d = dt.date(yr, mo, da)
    except (ValueError, TypeError):
        d = None
    return d, (m.group(4).strip() or None)


# --------------------------------------------------------------------------
# Movement normalization
# --------------------------------------------------------------------------

TOKEN_FIXES = [
    (r"\bjumpign\b", "jumping"),
    (r"\balter?n?a?i?ting\b|\balterating\b|\balternataing\b", "alternating"),
    (r"\bdead(?:ift|ilft)s?\b", "deadlifts"),
    (r"\brevese\b", "reverse"),
    (r"\bmorings?\b", "mornings"),
    (r"\boverehads?\b", "overheads"),
    (r"\bsquezers?\b", "squeezers"),
    (r"\bpresss\b", "press"),
    (r"\bpowere\b", "power"),
    (r"\blaterial\b", "lateral"),
    (r"\bbarbell\s+", ""),
    (r"\bdumbbells?\b|\bdb'?s\b", "DB"),
    (r"\bkettlebells?\b|\bkb'?s\b", "KB"),
    (r"\bpush[- ]?ups?\b", "push ups"),
    (r"\bsit[- ]?ups?\b", "sit ups"),
    (r"\bpull[- ]?ups?\b", "pull ups"),
    (r"\bstep[- ]?ups?\b", "step ups"),
    (r"\bv[- ]?ups?\b", "v-ups"),
    (r"\bup ?/ ?downs?\b", "up/downs"),
    (r"\bdead ?lifts?\b", "deadlifts"),
    (r"\brdls?\b", "romanian deadlifts"),
    (r"\bhpcs?\b", "hang power cleans"),
    (r"\bkbs\b", "KB swings"),
]
KEEP_UPPER = {"db": "DB", "kb": "KB", "2db": "2DB", "ab": "Ab"}
SYNONYMS = {
    "Plank": "Plank Hold",
    "Jumping Jack": "Jumping Jack",
    "Toe Tap": "Toe Tap",
    "Sumo Dead Lift": "Sumo Deadlift",
    "Burpies": "Burpee",
    "Inchworm": "Inch Worm",
    "Inchworm Shoulder Tap": "Inch Worm Shoulder Tap",
    "Plate Ground To Overheads": "Plate Ground To Overhead",
    "Australian Pull Up": "Australian Pull Up",
    "Barbell Good Morning": "Good Morning",
    "Hollow Hold": "Hollow Hold",
    "DB Curl + Press": "DB Curl + DB Press",
    "Lunge Per Leg": "Lunge",
    "DB Hang Power Clean + Press": "DB Hang Power Clean + Push Press",
    "KB/DB Swing": "KB Swing",
}
NO_SINGULAR = {"press", "abs", "plus", "across", "cross", "pass", "toss"}


def singular(word):
    lw = word.lower()
    if lw == "ups":
        return word[:-1]
    if lw in NO_SINGULAR or lw.endswith("ss") or len(lw) <= 3:
        return word
    if "/" in word:
        return "/".join(singular(w) for w in word.split("/"))
    if lw.endswith(("ches", "shes", "xes", "sses")):
        return word[:-2]
    if lw.endswith("ies") and len(lw) > 4:
        return word[:-3] + "y"
    if lw.endswith("s") and not lw.endswith(("us", "is")):
        return word[:-1]
    return word


def titlecase(word):
    lw = word.lower()
    if lw in KEEP_UPPER:
        return KEEP_UPPER[lw]
    if lw.startswith("v-"):
        return "V-" + lw[2:].capitalize()
    if "/" in word:
        return "/".join(titlecase(w) for w in word.split("/"))
    return lw[:1].upper() + lw[1:]


def canonical_movement(name):
    """Return (canonical_name, attrs dict) for a raw movement string."""
    attrs = {}
    s = norm_ws(name)
    s = s.strip(" .,;:-")
    # qualifiers
    m = re.search(r"\s*\(?\b(each side|per side|each leg|per leg|each arm|per arm|e/s)\b\)?\s*$", s, re.I)
    if m:
        attrs["per_side"] = True
        s = s[: m.start()]
    m = re.search(r"\s*\((\d\s*DB|single DB)\)\s*$", s, re.I)
    if m:
        attrs["implement_note"] = m.group(1)
        s = s[: m.start()]
    low = s.lower()
    for pat, rep in TOKEN_FIXES:
        low = re.sub(pat, rep, low, flags=re.I)
    if re.match(r"^(alternating|alt\.?)\s+", low):
        attrs["alternating"] = True
        low = re.sub(r"^(alternating|alt\.?)\s+", "", low)
    parts = [p.strip() for p in re.split(r"\s*\+\s*", low) if p.strip()]
    out_parts = []
    for p in parts:
        words = [titlecase(w) for w in p.split()]
        if words:
            words[-1] = singular(words[-1])
        out_parts.append(" ".join(words))
    canon = " + ".join(out_parts)
    canon = SYNONYMS.get(canon, canon)
    return canon or None, attrs


# --------------------------------------------------------------------------
# Format parsing
# --------------------------------------------------------------------------

REST_ROUND_RE = re.compile(
    r"\(\s*REST\s+(\d+)\s*(MIN|SEC)\.?(?:\s+(?:AFTER EACH|BETWEEN)\s+ROUNDS?)?\s*(?:\)|$)", re.I)

# header regexes: (regex, builder(match) -> format dict)
def _i(x):
    return int(x) if x is not None else None


def _ladder_dir(scheme):
    nums = [int(n) for n in re.findall(r"\d+", scheme)]
    if len(nums) < 2:
        return None
    if all(a > b for a, b in zip(nums, nums[1:])):
        return "descending"
    if all(a < b for a, b in zip(nums, nums[1:])):
        return "ascending"
    return "pyramid"


HEADERS = [
    (r"^(\d+)\s*Total Rounds:?\s*\(\s*AMRAP in (\d+)\s*min\.?\s*\)\s*:?\s*(?:\(\s*(\d+(?:-\d+)*)\s*\.\.\.\s*Reps\s*\)\s*:?)?",
     lambda m: dict(type="amrap", rounds=_i(m.group(1)), duration_min=_i(m.group(2)),
                    **({"reps_scheme": m.group(3) + "...", "ladder": "ascending"} if m.group(3) else {}))),
    (r"^(\d+)\s*Total Rounds:?\s*\(\s*(\d+)\s*Sec\.?\s*WORK\.?\s*/\s*(\d+)\s*Sec\.?\s*REST\.?\s*\)\s*:?",
     lambda m: dict(type="interval", rounds=_i(m.group(1)), work_sec=_i(m.group(2)), rest_sec=_i(m.group(3)))),
    (r"^(\d+)\s*Total Rounds:?\s*\(\s*(\d+)\s*Min\.?\s*Per Station\s*\)\s*:?",
     lambda m: dict(type="interval", rounds=_i(m.group(1)), work_sec=60 * int(m.group(2)), per_station=True)),
    (r"^(\d+)\s*Rounds:?\s*\(?\s*(\d+)\s*Sec\.?\s*WORK\.?\s*/\s*(\d+)\s*Sec\.?\s*REST\.?\s*\)?\s*:?",
     lambda m: dict(type="interval", rounds=_i(m.group(1)), work_sec=_i(m.group(2)), rest_sec=_i(m.group(3)))),
    (r"^AMRAP in (\d+)\s*min\.?\s*:?",
     lambda m: dict(type="amrap", duration_min=_i(m.group(1)))),
    (r"^(\d+(?:\s*-\s*\d+)+)\s*Reps?\s*For Time\s*:?",
     lambda m: dict(type="for_time", reps_scheme=re.sub(r"\s+", "", m.group(1)),
                    ladder=_ladder_dir(m.group(1)))),
    (r"^(\d+)\s*Rounds? For Time\s*:?",
     lambda m: dict(type="for_time", rounds=_i(m.group(1)))),
    (r"^Every (\d+) Min\.? For (\d+) Min\.?\s*:?",
     lambda m: dict(type="every_n_min", interval_min=_i(m.group(1)), duration_min=_i(m.group(2)),
                    rounds=int(m.group(2)) // max(1, int(m.group(1))))),
    (r"^E(\d+)MOM For (\d+) Min\.?\s*:?",
     lambda m: dict(type="every_n_min", interval_min=_i(m.group(1)), duration_min=_i(m.group(2)),
                    rounds=int(m.group(2)) // max(1, int(m.group(1))))),
    (r"^(?:Every Min\.?|EMOM) For (\d+) Min\.?\s*:?",
     lambda m: dict(type="emom", interval_min=1, duration_min=_i(m.group(1)), rounds=_i(m.group(1)))),
    (r"^Tabata\b\s*:?",
     lambda m: dict(type="tabata", rounds=8, work_sec=20, rest_sec=10)),
    (r"^(\d+(?:\s*-\s*\d+)+)\s*:",
     lambda m: dict(type="ladder", reps_scheme=re.sub(r"\s+", "", m.group(1)), ladder=_ladder_dir(m.group(1)))),
    (r"^(\d+)\s*(?:Total\s*)?Rounds\s*:?",
     lambda m: dict(type="rounds", rounds=_i(m.group(1)))),
]
HEADERS = [(re.compile(p, re.I), b) for p, b in HEADERS]

# whole-cell "sets" patterns (no header, e.g. accessory or plain strength sets)
SETS_PATTERNS = [
    # "Strict Sit Ups: 15-15-15-15-15"  / "Push Press: 10-8-6-4-2 Reps"
    (re.compile(r"^(?P<mv>[A-Za-z][^:]*?):\s*(?P<scheme>\d+(?:\s*-\s*\d+){1,})\s*(?:Reps)?\.?$", re.I), "scheme"),
    # "Plank Holds: 45 Sec. x 5" / "... x 5 Rounds"
    (re.compile(r"^(?P<mv>[A-Za-z][^:]*?):\s*(?P<sec>\d+)\s*Sec\.?\s*x\s*(?P<sets>\d+)\s*(?:Rounds|Sets)?\.?$", re.I), "timed"),
    # "Hollow Rocks: 5 Sets of 15 Reps" / "Plank Holds: 5 Sets of 45 Sec. Holds"
    (re.compile(r"^(?P<mv>[A-Za-z][^:]*?):\s*(?P<sets>\d+)\s*Sets of\s*(?P<n>\d+)\s*(?P<unit>Reps|Sec\.?(?:\s*Holds?)?)\.?$", re.I), "setsof"),
    # "Leg Raises: 15 Reps x 5 Rounds"
    (re.compile(r"^(?P<mv>[A-Za-z][^:]*?):\s*(?P<n>\d+)\s*Reps\s*x\s*(?P<sets>\d+)\s*(?:Rounds|Sets)?\.?$", re.I), "repsx"),
    # "Back squats 5 rep x 6"
    (re.compile(r"^(?P<mv>[A-Za-z][A-Za-z ]*?)\s+(?P<n>\d+)\s*reps?\s*x\s*(?P<sets>\d+)\.?$", re.I), "repsx"),
    # "1 rep max back squat"
    (re.compile(r"^(?P<n>\d+)\s*rep max\s+(?P<mv>.+)$", re.I), "max"),
]

MOBILITY_RE = re.compile(r"^(stretching|mobility|mobilizing|foam roll)", re.I)
CARDIO_RE = re.compile(r"^(cycling|cycle|bike|biking|swim|swam|run|ran|walk|walked|row|rowing|hike|hiked)\b.*?(\d+)\s*(min|mins|minutes|yards|yd|m|miles?)\b", re.I)


def parse_item_text(text):
    """'5 Front Squats' -> item dict (without letter)."""
    item = {}
    t = norm_ws(text).strip(" .;,")
    t = re.sub(r"^([A-H])\s*:\s*", "", t)          # duplicated letter "B: B: 15 ..."
    t = re.sub(r"^(\d+)\.\s+", r"\1 ", t)          # "4. Alternating Lunges"
    if not t:
        return None
    # complexes: "3 Power Cleans + 3 Front Squats"
    if "+" in t and re.search(r"\+\s*\d+\s+[A-Za-z]", t):
        parts = []
        for p in re.split(r"\s*\+\s*", t):
            pm = re.match(r"^(\d+)\s+(.*)$", p)
            mv, _ = canonical_movement(pm.group(2) if pm else p)
            parts.append({"reps": int(pm.group(1)) if pm else None, "movement": mv})
        item["complex"] = parts
        item["reps"] = parts[0]["reps"]
        item["movement"] = " + ".join(p["movement"] for p in parts)
        item["movement_raw"] = t
        return item
    # inline weights: "95lb deadlift", "Deadlift @ 95lb", "2b ..."
    m = re.match(r"^(\d+(?:\.\d+)?)\s*(lbs?|#|kg)\s+(.*)$", t, re.I)
    if m:
        w = float(m.group(1))
        if m.group(2).lower() == "kg":
            item["weight_note"] = f"{m.group(1)}kg"
            w = round(w * KG_TO_LB, 1)
        item["weight_lb"] = int(w) if float(w).is_integer() else w
        t = m.group(3)
    m = re.search(r"\s*@\s*(\d+(?:\.\d+)?)\s*(lbs?|#)\s*$", t, re.I)
    if m:
        item["weight_lb"] = int(float(m.group(1)))
        t = t[: m.start()]
    # percent scheme: "5 Back Squats: 50%, 60%, 70%, (80% x 3)"
    m = re.match(r"^(.*?):\s*((?:\(?\s*\d+\s*%\s*(?:x\s*\d+)?\s*\)?\s*,?\s*)+)$", t)
    if m:
        pcts = []
        for pm in re.finditer(r"(\d+)\s*%\s*(?:x\s*(\d+))?", m.group(2)):
            pcts += [int(pm.group(1))] * (int(pm.group(2)) if pm.group(2) else 1)
        item["percent_scheme"] = pcts
        t = m.group(1)
    # "Push Press: 10-8-6-4-2 Reps"
    m = re.match(r"^(.*?):\s*(\d+(?:\s*-\s*\d+)+)\s*(?:Reps)?$", t, re.I)
    if m:
        item["reps_scheme"] = re.sub(r"\s+", "", m.group(2))
        t = m.group(1)
    m = re.match(r"^(\d+)\s*(?:Sec\.?|Seconds?|s)\s+(.*)$", t, re.I)
    if m:
        item["time_sec"] = int(m.group(1))
        t = m.group(2)
    else:
        m = re.match(r"^(\d+)\s*(?:Min\.?|Minutes?)\s+(.*)$", t, re.I)
        if m:
            item["time_sec"] = int(m.group(1)) * 60
            t = m.group(2)
        else:
            m = re.match(r"^(\d+)\s*(?:m|Meters?)\s+(.*)$", t, re.I)
            if m:
                item["distance_m"] = int(m.group(1))
                t = m.group(2)
            else:
                m = re.match(r"^(\d+)\s*(?:Cal\.?|Calories)\s+(.*)$", t, re.I)
                if m:
                    item["calories"] = int(m.group(1))
                    t = m.group(2)
                else:
                    m = re.match(r"^(\d+)\s*/\s*(\d+)\s+(.*)$", t)
                    if m:
                        item["reps"] = int(m.group(1))
                        item["reps_note"] = f"{m.group(1)}/{m.group(2)}"
                        t = m.group(3)
                    else:
                        m = re.match(r"^(\d+)\s+(.*)$", t)
                        if m:
                            item["reps"] = int(m.group(1))
                            t = m.group(2)
    m = re.search(r"\s+(?:x\s*)?(\d+)\s*(?:Sec\.?|Seconds?)\s*$", t, re.I)
    if m and "time_sec" not in item:
        item["time_sec"] = int(m.group(1))
        t = t[: m.start()]
    if not re.search(r"[A-Za-z]", t):
        return item or None
    mv, attrs = canonical_movement(t)
    item["movement"] = mv
    item["movement_raw"] = norm_ws(t)
    item.update(attrs)
    return item


def split_lettered(body):
    """Split 'A: 5 X / B: 10 Y' into [('A','5 X'), ('B','10 Y')]. Returns None if
    no letters."""
    b = body.strip()
    if not re.match(r"^[A-H]\s*(?::|=|\s(?=\d))", b):
        return None
    marks = []
    for m in re.finditer(r"(?:^|/\s*)([A-H])\s*(?::|=|\s(?=\d))\s*", b):
        marks.append((m.start(), m.end(), m.group(1)))
    out = []
    for i, (s, e, letter) in enumerate(marks):
        end = marks[i + 1][0] if i + 1 < len(marks) else len(b)
        out.append((letter, b[e:end].strip(" /")))
    return out


def parse_section_text(raw, kind):
    """Return (format|None, items list, extra_notes list)."""
    text = norm_ws(raw)
    if re.fullmatch(r"n/?a\.?|none|-+|rest|off", text, re.I):
        return {"type": "none"}, [], []
    fmt = None
    body = text
    # rest after each round
    rest_round = None
    m = REST_ROUND_RE.search(body)
    if m:
        rest_round = int(m.group(1)) * (60 if m.group(2).upper().startswith("MIN") else 1)
        body = (body[: m.start()] + body[m.end():]).strip()
    for rx, build in HEADERS:
        m = rx.match(body)
        if m:
            fmt = {k: v for k, v in build(m).items() if v is not None}
            body = body[m.end():].strip()
            break
    if fmt is None:
        if MOBILITY_RE.match(text):
            return {"type": "other", "category": "mobility"}, [
                {"letter": None, "movement": "Stretching / Mobility", "movement_raw": text}], []
        m = CARDIO_RE.match(text)
        if m:
            unit = m.group(3).lower()
            mv, _ = canonical_movement(m.group(1))
            mv = {"Cycling": "Cycling", "Cycle": "Cycling", "Bike": "Cycling", "Biking": "Cycling",
                  "Swam": "Swim", "Ran": "Run", "Walked": "Walk", "Rowing": "Row", "Hiked": "Hike"}.get(mv, mv)
            item = {"letter": None, "movement": mv, "movement_raw": text}
            if unit.startswith("min"):
                item["time_sec"] = int(m.group(2)) * 60
            else:
                item["distance"] = f"{m.group(2)} {unit}"
            return {"type": "other", "category": "cardio"}, [item], []
        for rx, kindp in SETS_PATTERNS:
            m = rx.match(text)
            if not m:
                continue
            g = m.groupdict()
            mv, attrs = canonical_movement(g["mv"])
            item = {"letter": None, "movement": mv, "movement_raw": norm_ws(g["mv"]), **attrs}
            fmt = {"type": "sets"}
            if kindp == "scheme":
                scheme = re.sub(r"\s+", "", g["scheme"])
                reps = [int(x) for x in scheme.split("-")]
                fmt["sets"] = len(reps)
                item["reps_scheme"] = scheme
                if len(set(reps)) == 1:
                    item["reps"] = reps[0]
            elif kindp == "timed":
                fmt["sets"] = int(g["sets"])
                item["time_sec"] = int(g["sec"])
            elif kindp == "setsof":
                fmt["sets"] = int(g["sets"])
                if g["unit"].lower().startswith("rep"):
                    item["reps"] = int(g["n"])
                else:
                    item["time_sec"] = int(g["n"])
            elif kindp == "repsx":
                fmt["sets"] = int(g["sets"])
                item["reps"] = int(g["n"])
            elif kindp == "max":
                fmt["test"] = f"{g['n']}RM"
                item["reps"] = int(g["n"])
            return fmt, [item], []
        return None, [], []
    if rest_round is not None:
        fmt["rest_between_rounds_sec"] = rest_round
    items = []
    body = body.strip(" :")
    if body:
        lettered = split_lettered(body)
        if lettered:
            expanded = []
            for letter, t in lettered:
                # "C: 6 Air Squats / 7 KB Swings" -> missing letter for the 2nd item
                subs = re.split(r"\s+/\s+(?=\d)", t)
                expanded.append((letter, subs[0], False))
                for k, sub in enumerate(subs[1:], 1):
                    expanded.append((chr(ord(letter) + k), sub, True))
            for letter, t, inferred in expanded:
                it = parse_item_text(t)
                if it is not None and inferred:
                    it["letter_inferred"] = True
                if it is None:
                    items.append({"letter": letter, "movement": None, "movement_raw": t})
                else:
                    items.append({"letter": letter, **it})
        elif fmt.get("type") == "ladder" or ("," in body and not re.search(r"\d+\s*%", body)):
            for t in [p for p in re.split(r"\s*,\s*", body) if p.strip()]:
                it = parse_item_text(t)
                if it:
                    items.append({"letter": None, **it})
        else:
            it = parse_item_text(body)
            if it:
                items.append({"letter": None, **it})
    return fmt, items, []


# --------------------------------------------------------------------------
# Notes parsing
# --------------------------------------------------------------------------

def parse_weight_value(val):
    """'35lb' -> (35, None); 'empty barbell, take from rack' -> (45, note)."""
    v = norm_ws(val)
    note = None
    m = re.search(r"(\d+(?:\.\d+)?)\s*(lbs?|#|kg)\b", v, re.I)
    if m:
        w = float(m.group(1))
        if m.group(2).lower() == "kg":
            w = round(w * KG_TO_LB, 1)
            note = v
        w = int(w) if float(w).is_integer() else w
        if not re.fullmatch(r"\d+(?:\.\d+)?\s*(lbs?|#)", v, re.I):
            note = v
        return w, note
    if re.search(r"\bempty (bar|barbell)\b", v, re.I):
        return EMPTY_BARBELL_LB, v
    if re.search(r"\b(body bar)\b", v, re.I):
        return None, v
    return None, v if v else None


LOADABLE_RE = re.compile(r"\b(DB|KB|Plate|Deadlift|Clean|Snatch|Press|Jerk|Thruster|Swing|Row|Front Squat|Back Squat|"
                         r"Goblet|Good Morning|Overhead)\b")


def apply_coach_weights(items, coach_note):
    """Map 'A = 35lb / B = 20lb' style coach notes onto items by letter.

    A bare weight segment without a letter ("A = hold db's at sides / 20lb",
    "A = 15lb / 35lb") is attributed to the previous letter group when that
    group had no weight, otherwise to the next letter; such items get
    `weight_letter_inferred: true`.
    """
    if not coach_note or not items:
        return 0
    mapped = 0
    by_letter = {it.get("letter"): it for it in items if it.get("letter")}
    single = items[0] if len(items) == 1 else None
    prev_letters, prev_had_weight = None, False
    for seg in re.split(r"\s+/\s+|\n+", coach_note):
        seg = seg.strip()
        m = re.match(r"^([A-H](?:\s*(?:&|and|,|\+)\s*[A-H])*)\s*=\s*(.+)$", seg)
        if not m:
            bare = re.fullmatch(r"(\d+(?:\.\d+)?)\s*(lbs?|#)", seg, re.I)
            if bare and prev_letters:
                w = int(float(bare.group(1))) if float(bare.group(1)).is_integer() else float(bare.group(1))
                if not prev_had_weight:
                    targets = prev_letters
                else:
                    targets = [chr(ord(max(prev_letters)) + 1)]
                for L in targets:
                    it = by_letter.get(L)
                    if it is not None and prev_had_weight and not LOADABLE_RE.search(it.get("movement") or ""):
                        continue  # don't push a weight onto a bodyweight movement
                    if it is not None and it.get("weight_lb") is None:
                        it["weight_lb"] = w
                        it["weight_letter_inferred"] = True
                        mapped += 1
                prev_letters, prev_had_weight = targets, True
            continue
        letters = re.findall(r"[A-H]", m.group(1))
        w, note = parse_weight_value(m.group(2))
        pbw = re.search(r"(\d+)\s*%\s*of\s*body\s*weight", m.group(2), re.I)
        for L in letters:
            it = by_letter.get(L) or (single if (single and L == "A" and not single.get("letter")) else None)
            if it is None:
                continue
            if w is not None and it.get("weight_lb") is None:
                it["weight_lb"] = w
                mapped += 1
            if pbw:
                it["percent_bodyweight"] = int(pbw.group(1))
            if note:
                it["coach_cue"] = note if not it.get("coach_cue") else it["coach_cue"] + " / " + note
        prev_letters, prev_had_weight = letters, w is not None
    return mapped


SUBSTITUTION_RE = re.compile(r"\b(db|dumbbell|bench press|machine|switched|adjusted|instead|sub(bed)?)\b", re.I)


def parse_logged_weights_with_source(note):
    """Return (weights|None, source). source is 'leading' for a list at the
    start of the note, 'after_text' for a >=3 number list after a leading
    sentence (e.g. "Kept it light. 65,75,85"), skipped when the note mentions a
    substitution (db / machine / bench press ...)."""
    w = parse_logged_weights(note)
    if w:
        return w, "leading"
    if not note or SUBSTITUTION_RE.search(note):
        return None, None
    for m in re.finditer(r"[.!]\s+(?=\d)", note):
        w = parse_logged_weights(note[m.end():])
        if w and len(w) >= 3:
            return w, "after_text"
    return None, None


def parse_logged_weights(note):
    """Leading comma-separated number list -> list of numbers, else None."""
    if not note:
        return None
    s = note.strip()
    if not re.match(r"^\d", s):
        return None
    out = []
    pos = 0
    tok = re.compile(
        r"\s*(\d{1,3}(?:\.\d+)?)\s*(lbs?\b|#)?\s*(?:x\s*\d+|\(\s*\d+\s*(?:reps?|rep)?\s*\))?\s*"
    )
    while True:
        m = tok.match(s, pos)
        if not m:
            break
        nxt = s[m.end(): m.end() + 3].lower()
        if re.match(r"(lb\s*d|db)", nxt):  # e.g. "15lb db" -> not a barbell set
            break
        val = float(m.group(1))
        # stop on things like "15# rows" or "15lb db"
        tail = s[m.end():]
        if m.group(2) and re.match(r"(db|rows?|kb)\b", tail, re.I):
            break
        out.append(int(val) if val.is_integer() else val)
        pos = m.end()
        if pos < len(s) and s[pos] == ",":
            pos += 1
            continue
        # ". 135" continuation like "125. 135"
        m2 = re.match(r"\.\s*(?=\d{2,3}\b(?!\s*(?:lb|#)?\s*[a-z]))", s[pos:])
        if m2 and re.match(r"\.\s*\d{2,3}\s*(,|$)", s[pos:]):
            pos += m2.end()
            continue
        break
    # drop an obviously truncated trailing value, e.g. "65, 80, 95, 110, 1"
    if len(out) >= 3 and out[-1] < 20 and min(out[:-1]) >= 30:
        out = out[:-1]
    return out or None


SCORE_TOKEN = re.compile(
    r"(?P<tok>\d+\s*\+\s*\d+|\d+\s*[:;]\s*\d{2}(?::\d{2})?|:\d{2}|\d+(?:\.\d+)?)"
    r"(?P<rounds>\s*rounds?\b)?"
)


def _norm_score(tok):
    t = re.sub(r"\s+", "", tok)
    t = t.replace(";", ":")
    if re.fullmatch(r"\d+:\d{2}:00", t):  # 19:28:00 from Excel time
        t = t[:-3]
    return t


def parse_scores(note):
    """Extract a leading list of scores ('5+1,5+5', '14:25', '10 rounds')."""
    if not note:
        return None
    s = note.strip()
    # drop leading weight annotations: "85lb 15:54", "10lb, 35lb, 22lb.  10+7", "10lb B, 16:04"
    s = re.sub(r"^(?:[A-D]?\s*\d+\s*(?:lbs?|#|kg)\s*(?:[A-D]\b)?\s*[,.]?\s*)+", "", s, flags=re.I)
    starts = [0] + [m.end() for m in re.finditer(r"[.!]\s+", s)]
    for st in starts:
        out = []
        pos = st
        while True:
            m = SCORE_TOKEN.match(s, pos)
            if not m:
                break
            after = s[m.end(): m.end() + 4]
            if re.match(r"\s*(lb|#|kg|min|sec|%|rest\b)", after, re.I) or re.match(r"[A-Za-z]", after):
                break
            tok = m.group("tok")
            # big integer floats from Excel (e.g. "157146186") are lost commas -> not a score
            if re.fullmatch(r"\d{4,}", tok):
                return None
            out.append(_norm_score(tok))
            pos = m.end()
            m2 = re.match(r"\s*,?\s*(?:\([^)]*\)\s*,?\s*)?", s[pos:])  # "," and/or "(moved to 10# db)"
            if m2 and m2.group(0).strip():
                pos += m2.end()
                continue
            break
        if out:
            return out
    return None


SKIP_RE = re.compile(r"^\s*skip\b|\b(did not do|didn'?t do|skipped|did not complete|missed (this|the) workout|sick)\b", re.I)


# --------------------------------------------------------------------------
# Sheet reading
# --------------------------------------------------------------------------

def read_tabs(path):
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    tabs = []
    for name in wb.sheetnames:
        ws = wb[name]
        rows = [list(r) for r in ws.iter_rows(min_row=1, max_row=60, max_col=20, values_only=True)]
        tabs.append((name, rows))
    wb.close()
    return tabs


def week_sort_key(name):
    m = re.match(r"\s*Week\s+(\d+)", name, re.I)
    return int(m.group(1)) if m else 10**6


def import_workbook(path, today):
    tabs = read_tabs(path)
    tabs.sort(key=lambda t: week_sort_key(t[0]))
    workouts = []
    quirks = []
    prev_monday = None
    prev_week_notes = {}  # (weekday, kind) -> athlete note of previous week
    for name, rows in tabs:
        # header row: first row containing 'Monday'
        hdr_idx = next((i for i, r in enumerate(rows[:10])
                        if any(isinstance(c, str) and c.strip().lower() == "monday" for c in r)), None)
        if hdr_idx is None:
            quirks.append(f"{name}: no header row with day names; tab skipped")
            continue
        hdr = rows[hdr_idx]
        day_cols = {}
        comments_col = None
        for c, v in enumerate(hdr):
            if isinstance(v, str):
                vv = v.strip().lower()
                for d in DAY_NAMES:
                    if vv == d.lower():
                        day_cols[d] = c
                if vv == "comments":
                    comments_col = c
        date_row = rows[hdr_idx + 1] if hdr_idx + 1 < len(rows) else []
        if sorted(day_cols.values()) != list(range(1, 1 + len(day_cols))):
            quirks.append(f"{name}: day columns not contiguous (columns {sorted(day_cols.values())}); mapped by header text")
        # Monday from sheet vs tab name
        sheet_mon, _ = parse_sheet_date(date_row[day_cols["Monday"]] if "Monday" in day_cols else None,
                                        prev_monday.year if prev_monday else None)
        tab_mon = tab_monday(name, prev_monday, sheet_mon)
        monday = sheet_mon
        flags_week = []
        if sheet_mon is None or sheet_mon.weekday() != 0:
            monday = tab_mon
            flags_week.append("date_from_tab_name")
            quirks.append(f"{name}: sheet Monday date missing/invalid; used tab name -> {tab_mon}")
        elif tab_mon and sheet_mon != tab_mon:
            monday = tab_mon
            flags_week.append("date_from_tab_name")
            quirks.append(f"{name}: sheet dates say week of {sheet_mon} but tab name says {tab_mon} "
                          f"(dates likely copy-pasted from previous tab); used tab name")
        if prev_monday and monday and (monday - prev_monday).days != 7:
            quirks.append(f"{name}: {(monday - prev_monday).days // 7 - 1} week(s) without a tab before this one "
                          f"({prev_monday} -> {monday})")
        # label rows
        sections_rows = []  # (kind, label_row_idx, coach_row_idx, athlete_row_idx)
        current = None
        for i in range(hdr_idx + 2, len(rows)):
            lab = rows[i][0] if rows[i] else None
            if not isinstance(lab, str):
                continue
            l = norm_ws(lab).lower()
            if l in SECTION_LABELS:
                current = {"kind": SECTION_LABELS[l], "label": lab.strip(), "row": i, "coach": None, "athlete": None}
                sections_rows.append(current)
            elif l.startswith("coach") and current:
                current["coach"] = i
            elif l.startswith("athlete") and current:
                current["athlete"] = i
            elif l not in ("——", "-", ""):
                quirks.append(f"{name}: unknown row label {lab!r} at row {i + 1}")
        week_notes = {}
        for d, col in sorted(day_cols.items(), key=lambda kv: DAY_NAMES.index(kv[0])):
            offset = DAY_NAMES.index(d)
            date = monday + dt.timedelta(days=offset) if monday else None
            sd, date_note = parse_sheet_date(date_row[col] if col < len(date_row) else None,
                                             monday.year if monday else None)
            wflags = list(flags_week)
            if sd and date and sd != date and "date_from_tab_name" not in flags_week:
                # string dates like "6/5 - ZOOM" have a guessed year; compare month/day
                if (sd.month, sd.day) != (date.month, date.day):
                    wflags.append("sheet_date_mismatch")
                    quirks.append(f"{name} {d}: sheet date {sd} != expected {date}")
            secs = []
            for srow in sections_rows:
                def g(idx):
                    if idx is None or idx >= len(rows) or col >= len(rows[idx]):
                        return None
                    return cell_text(rows[idx][col])
                raw = g(srow["row"])
                coach = g(srow["coach"])
                ath = g(srow["athlete"])
                if raw is None and coach is None and ath is None:
                    continue
                week_note = None
                if comments_col is not None and comments_col < len(rows[srow["row"]]):
                    week_note = cell_text(rows[srow["row"]][comments_col])
                sec = {"kind": srow["kind"], "raw": raw, "coach_note": coach, "athlete_note": ath}
                if week_note:
                    sec["week_note"] = week_note
                secs.append(sec)
            if not secs:
                continue
            # Off-program sessions (e.g. "cycling for 30min" in the Warm Up row,
            # or only an athlete comment like "Swam 800 yards")
            programmed = [s for s in secs if s["raw"]]
            for s in secs:
                if s["raw"] is None and not programmed:
                    s["kind"] = "other"
                elif s["kind"] == "warmup" and s["raw"] and CARDIO_RE.match(s["raw"]) and len(programmed) == 1:
                    s["kind"] = "other"
            noted = []
            for s in secs:
                parse_section(s)
                note = s["athlete_note"]
                if note:
                    week_notes[(d, s["kind"])] = note
                    noted.append(s)
                if note and SKIP_RE.search(note):
                    s["athlete_reported_skip"] = True
                    wflags.append("athlete_reported_skip_or_sick")
            # Copy-pasted athlete notes: the new tab was cloned from the previous
            # one and old notes left in place. Flag when every athlete note of the
            # day equals last week's same-day note and either there are >= 2 of
            # them or the date is still in the future. (A single matching weight
            # list like "45, 55, 65, 75, 85" is common and treated as genuine.)
            dup = [s for s in noted if len(s["athlete_note"]) > 3
                   and prev_week_notes.get((d, s["kind"])) == s["athlete_note"]]
            future = bool(date and date > today)
            if dup and len(dup) == len(noted) and (len(dup) >= 2 or future):
                for s in dup:
                    s["athlete_note_duplicate_of_previous_week"] = True
                wflags.append("athlete_note_copied_from_previous_week")
            if future:
                wflags.append("future_date")
            w = {"date": date.isoformat() if date else None, "weekday": DAY_ABBR[d], "source_tab": name}
            if date_note:
                w["date_note"] = date_note
            if wflags:
                w["flags"] = sorted(set(wflags))
            w["sections"] = secs
            workouts.append(w)
        prev_week_notes = week_notes
        if monday:
            prev_monday = monday
    workouts.sort(key=lambda w: (w["date"] or "", DAY_NAMES.index(next(k for k, v in DAY_ABBR.items() if v == w["weekday"]))))
    return workouts, quirks


def parse_section(s):
    raw = s["raw"]
    s["format"] = None
    s["items"] = []
    if raw:
        fmt, items, _ = parse_section_text(raw, s["kind"])
        s["format"] = fmt
        s["items"] = items
        apply_coach_weights(items, s["coach_note"])
    if s["kind"] == "strength":
        w, src = parse_logged_weights_with_source(s["athlete_note"])
        s["logged_weights_lb"] = w
        if src == "after_text":
            s["logged_weights_source"] = src
    if s["kind"] == "metabolic":
        s["logged_scores"] = parse_scores(s["athlete_note"])


# --------------------------------------------------------------------------
# Movements + report
# --------------------------------------------------------------------------

def build_movements(workouts):
    agg = {}
    for w in workouts:
        for s in w["sections"]:
            for it in s.get("items", []):
                mv = it.get("movement")
                if not mv:
                    continue
                a = agg.setdefault(mv, {"name": mv, "count": 0, "section_kinds": collections.Counter(),
                                        "raw_variants": collections.Counter(), "first_date": w["date"],
                                        "last_date": w["date"]})
                a["count"] += 1
                a["section_kinds"][s["kind"]] += 1
                a["raw_variants"][it.get("movement_raw") or mv] += 1
                a["last_date"] = max(a["last_date"] or "", w["date"] or "")
    out = []
    for a in sorted(agg.values(), key=lambda x: (-x["count"], x["name"])):
        out.append({
            "name": a["name"],
            "count": a["count"],
            "section_kinds": dict(a["section_kinds"].most_common()),
            "raw_variants": [v for v, _ in a["raw_variants"].most_common()],
            "first_date": a["first_date"],
            "last_date": a["last_date"],
        })
    return out


def pattern_of(text):
    t = norm_ws(text)
    t = re.sub(r"\d+", "#", t)
    return t[:80]


def pct(n, d):
    return f"{100.0 * n / d:.1f}%" if d else "n/a"


def build_report(workouts, movements, quirks, src):
    L = []
    dates = [w["date"] for w in workouts if w["date"]]
    L.append("# Spreadsheet import report\n")
    L.append(f"Source: `{os.path.basename(src)}`  ")
    L.append(f"Generated by `tools/import_sheet.py` on {dt.date.today().isoformat()}\n")
    tabs = sorted({w["source_tab"] for w in workouts}, key=week_sort_key)
    L.append("## Summary\n")
    L.append(f"- Tabs imported: {len(tabs)} ({tabs[0]} to {tabs[-1]})")
    L.append(f"- Date range: {min(dates)} to {max(dates)}")
    L.append(f"- Workouts (day entries with any content): {len(workouts)}")
    wd = collections.Counter(w["weekday"] for w in workouts)
    L.append("- By weekday: " + ", ".join(f"{d[:3]} {wd.get(d[:3], 0)}" for d in DAY_NAMES if wd.get(d[:3])))
    flags = collections.Counter(f for w in workouts for f in w.get("flags", []))
    if flags:
        L.append("- Workout flags: " + ", ".join(f"`{k}` {v}" for k, v in flags.most_common()))
    L.append("")

    # coverage
    L.append("## Parse coverage by section\n")
    L.append("Sections whose raw text is `N/A` are excluded from the denominators. "
             "\"Items parsed\" = items with a recognized movement name / all items "
             "(sections with a recognized format but zero items count as one unparsed item). "
             "Athlete logs = strength weight lists or metabolic scores extracted / sections with an athlete note.\n")
    L.append("| Section | Count | Format recognized | Items parsed | Items w/ reps or time | Athlete notes | Logs parsed |")
    L.append("|---|---:|---:|---:|---:|---:|---:|")
    unparsed = collections.Counter()
    unparsed_examples = {}
    unparsed_logs = collections.Counter()
    for kind in ["warmup", "strength", "metabolic", "accessory", "other"]:
        secs = [s for w in workouts for s in w["sections"] if s["kind"] == kind and s["raw"]
                and (s["format"] or {}).get("type") != "none"]
        if not secs:
            continue
        fmt_ok = sum(1 for s in secs if s["format"])
        n_items = 0
        ok_items = 0
        dosed = 0
        for s in secs:
            if s["format"] and not s["items"]:
                n_items += 1
            for it in s["items"]:
                n_items += 1
                if it.get("movement"):
                    ok_items += 1
                if any(it.get(k) is not None for k in ("reps", "reps_scheme", "time_sec", "distance_m", "calories")):
                    dosed += 1
            if not s["format"]:
                p = pattern_of(s["raw"])
                unparsed[(kind, p)] += 1
                unparsed_examples.setdefault((kind, p), s["raw"])
        ath = [s for s in secs if s["athlete_note"] and not s.get("athlete_note_duplicate_of_previous_week")]
        if kind == "strength":
            logs = sum(1 for s in ath if s.get("logged_weights_lb"))
            for s in ath:
                if not s.get("logged_weights_lb"):
                    unparsed_logs[("strength", s["athlete_note"][:70])] += 1
            logs_s = pct(logs, len(ath))
        elif kind == "metabolic":
            logs = sum(1 for s in ath if s.get("logged_scores"))
            for s in ath:
                if not s.get("logged_scores"):
                    unparsed_logs[("metabolic", s["athlete_note"][:70])] += 1
            logs_s = pct(logs, len(ath))
        else:
            logs_s = "n/a"
        L.append(f"| {kind} | {len(secs)} | {pct(fmt_ok, len(secs))} | {pct(ok_items, n_items)} | "
                 f"{pct(dosed, n_items)} | {len(ath)} | {logs_s} |")
    L.append("")
    fmt_types = collections.Counter((s["kind"], (s["format"] or {}).get("type", "UNRECOGNIZED"))
                                    for w in workouts for s in w["sections"] if s["raw"])
    L.append("Format types found: " + "; ".join(
        f"{k}/{t} {v}" for (k, t), v in sorted(fmt_types.items(), key=lambda kv: (kv[0][0], -kv[1]))) + "\n")
    mapped = sum(1 for w in workouts for s in w["sections"] for it in s["items"] if it.get("weight_lb") is not None)
    total_items = sum(len(s["items"]) for w in workouts for s in w["sections"])
    L.append(f"Items with a prescribed weight (from coach notes or inline): {mapped} of {total_items}.\n")

    # top movements
    L.append("## Top 30 movements\n")
    L.append("| # | Movement | Count | Section kinds |")
    L.append("|---:|---|---:|---|")
    for i, m in enumerate(movements[:30], 1):
        kinds = ", ".join(f"{k} {v}" for k, v in m["section_kinds"].items())
        L.append(f"| {i} | {m['name']} | {m['count']} | {kinds} |")
    L.append(f"\n{len(movements)} distinct movements in total (see `data/movements.json`).\n")

    # six lifts
    L.append("## Six barbell lifts\n")
    L.append("Exact canonical movement match only: `DB`/`KB` variants, Romanian/Sumo/Reverse deadlifts, "
             "Power Clean and Hang Squat Clean are not counted. \"Strength sessions\" are strength sections "
             "where the lift is programmed; logged weights come from the athlete note (leading number list). "
             "When a strength section programs two movements the logged list is attributed to item A only. "
             "Logs flagged as copied from the previous week are ignored.\n")
    L.append("Future-dated (planned, not yet done) sessions are excluded from the counts and listed separately.\n")
    L.append("| Lift | Strength sessions | First | Last | With logged weights | Planned | Also in metcons/warm-ups | Last 3 logged weight lists (lb) |")
    L.append("|---|---:|---|---|---:|---:|---:|---|")
    lift_hist = {}
    for lift in SIX_LIFTS:
        sess = []
        other = 0
        planned = 0
        for w in workouts:
            if "future_date" in w.get("flags", []):
                planned += sum(1 for s in w["sections"] if s["kind"] == "strength"
                               and lift in [it.get("movement") for it in s["items"]])
                continue
            for s in w["sections"]:
                mvs = [it.get("movement") for it in s["items"]]
                if lift not in mvs:
                    continue
                if s["kind"] == "strength":
                    first_letter_item = s["items"][0] if s["items"] else {}
                    logs = s.get("logged_weights_lb")
                    if s.get("athlete_note_duplicate_of_previous_week"):
                        logs = None
                    if first_letter_item.get("movement") != lift:
                        logs = None
                    sess.append((w["date"], logs, s))
                else:
                    other += 1
        logged = [(d, l) for d, l, _ in sess if l]
        last3 = "; ".join(f"{d}: {', '.join(str(x) for x in l)}" for d, l in logged[-3:]) or "-"
        first = sess[0][0] if sess else "-"
        last = sess[-1][0] if sess else "-"
        L.append(f"| {lift} | {len(sess)} | {first} | {last} | {len(logged)} | {planned} | {other} | {last3} |")
        lift_hist[lift] = {"sessions": len(sess), "first": first, "last": last, "logged": len(logged),
                           "other": other, "last3": logged[-3:]}
    L.append("")

    # unparsed / partially parsed patterns
    L.append("## 15 most common unparsed patterns\n")
    L.append("Digits are replaced by `#`. Every section's format was recognized, so this list covers the "
             "remaining gaps: section text with no recognized format, items with no reps/time where the format "
             "expects one, coach-note `X = ...` segments that yielded no weight (often form cues, which is fine), "
             "coach weights with no letter, and athlete notes from which no weight list / score was extracted "
             "(notes with no digits at all are grouped as `<free text>`).\n")
    gaps = collections.Counter()
    for (k, p), v in unparsed.items():
        gaps[("format", k, p)] += v
    for (k, note), v in unparsed_logs.items():
        p = pattern_of(note) if re.search(r"\d", note) else "<free text, no numbers>"
        gaps[("athlete log", k, p)] += v
    for w in workouts:
        for s in w["sections"]:
            fmt = s.get("format") or {}
            if not s["raw"] or fmt.get("type") in (None, "none"):
                continue
            no_dose_ok = fmt.get("type") in ("for_time", "ladder", "interval", "other") or "reps_scheme" in fmt
            for it in s["items"]:
                dosed = any(it.get(k) is not None for k in
                            ("reps", "reps_scheme", "time_sec", "distance_m", "calories", "distance"))
                if not dosed and not no_dose_ok:
                    gaps[("item without reps/time", s["kind"], pattern_of(it.get("movement_raw") or ""))] += 1
            letters = {it.get("letter") for it in s["items"]}
            for seg in re.split(r"\s+/\s+|\n+", s["coach_note"] or ""):
                seg = seg.strip()
                m = re.match(r"^([A-H](?:\s*(?:&|and|,|\+)\s*[A-H])*)\s*=\s*(.+)$", seg)
                if m:
                    ls = re.findall(r"[A-H]", m.group(1))
                    if not any(L in letters for L in ls) and not (len(s["items"]) == 1 and ls == ["A"]):
                        gaps[("coach letter not in items", s["kind"], pattern_of(seg)[:60])] += 1
                    elif parse_weight_value(m.group(2))[0] is None:
                        gaps[("coach cue without weight", s["kind"], pattern_of(m.group(2))[:60])] += 1
                elif re.fullmatch(r"\d+(?:\.\d+)?\s*(lbs?|#)", seg, re.I) and not any(
                        it.get("weight_letter_inferred") for it in s["items"]):
                    gaps[("coach weight without letter", s["kind"], pattern_of(seg))] += 1
    L.append("| # | Gap type | Section | Pattern | Count |")
    L.append("|---:|---|---|---|---:|")
    for i, ((where, k, p), v) in enumerate(gaps.most_common(15), 1):
        L.append(f"| {i} | {where} | {k} | `{p.replace('|', '/')}` | {v} |")
    by_type = collections.Counter()
    for (where, _, _), v in gaps.items():
        by_type[where] += v
    L.append("\nTotals by gap type: " + ", ".join(f"{k} {v}" for k, v in by_type.most_common()) + ".\n")

    L.append("## Data quirks found while importing\n")
    for q in quirks:
        L.append(f"- {q}")
    L.append("- Excel auto-converted some metabolic scores typed as `mm:ss` into clock times "
             "(e.g. `19:28` stored as 19:28:00, `25:00` stored as 1 day 1:00). The importer reads "
             "them back as `mm:ss`.")
    L.append("- Some for-time scores are typed as decimals (`17.29`, `15.3`) or with semicolons (`21;07`). "
             "Semicolons are normalized to `:`; decimals are kept verbatim because `15.3` is ambiguous.")
    L.append("- A few metabolic scores lost their commas and became large numbers (e.g. `157146186`); "
             "these are not parsed as scores.")
    L.append("- Coach weights are usually per-letter (`A = 35lb / B = 20lb`); `empty bar(bell)` is mapped "
             f"to {EMPTY_BARBELL_LB} lb with the original text kept in `coach_cue`. Some cues are relative "
             "(\"complete all sets at 65% of bodyweight\", \"increase weight each set\") and have no weight.")
    L.append("- Strength athlete notes start with the set-by-set weights in most sessions; free-text-first "
             "notes (\"Worked up to 135#\", \"Decided to do bench press. 35, 45...\") are intentionally not "
             "parsed as logs, except that a list of 3+ numbers after a leading sentence is accepted "
             "(`logged_weights_source: \"after_text\"`) when the note does not mention a substitution "
             "(DB, machine, bench press, switched, ...).")
    L.append("- Coach notes sometimes give a weight without a letter (`A = hold db's at sides / 20lb`, "
             "`A = 15lb / 35lb`). The importer assigns it to the previous letter if that had no weight, else "
             "to the next loadable item, and marks the item `weight_letter_inferred: true`. "
             "`X% of bodyweight` cues are stored as `percent_bodyweight`.")
    L.append("- Weeks 4, 5 and 8 have a full Tuesday workout and a Wednesday dated `6/5 - ZOOM` etc. "
             "(kept as `date_note`). Other Tuesdays are off-program entries (cycling, a swim, a 1-rep-max "
             "back squat test whose warm-up ladder is in the coach note, not an athlete log).")
    L.append("- The newest tab (Week 123) was cloned from Week 122: its row-2 dates were not updated and the "
             "Wednesday/Friday athlete notes are copies of last week's. Those are flagged "
             "`athlete_note_copied_from_previous_week` + `future_date` and excluded from lift history.")
    L.append("- Complexes such as `3 Power Cleans + 3 Front Squats` are kept as one movement with a "
             "`complex` breakdown and are not counted toward the single-lift history.")
    L.append("")
    return "\n".join(L), lift_hist


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("xlsx", metavar="INPUT.xlsx", help="path to the coach's workbook")
    ap.add_argument("--out-dir", required=True, help="directory to write history.json, movements.json, import_report.md")
    ap.add_argument("--today", default=None, help="date used for the future_date flag (default: today)")
    args = ap.parse_args(argv)
    today = dt.date.fromisoformat(args.today) if args.today else dt.date.today()
    workouts, quirks = import_workbook(args.xlsx, today)
    movements = build_movements(workouts)
    report, lift_hist = build_report(workouts, movements, quirks, args.xlsx)
    os.makedirs(args.out_dir, exist_ok=True)
    with open(os.path.join(args.out_dir, "history.json"), "w") as f:
        json.dump(workouts, f, indent=2, ensure_ascii=False)
    with open(os.path.join(args.out_dir, "movements.json"), "w") as f:
        json.dump(movements, f, indent=2, ensure_ascii=False)
    with open(os.path.join(args.out_dir, "import_report.md"), "w") as f:
        f.write(report)
    print(f"{len(workouts)} workouts, {len(movements)} movements -> {args.out_dir}")


if __name__ == "__main__":
    main()
