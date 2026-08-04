#!/usr/bin/env python3
"""
Round 2: Fix remaining symbol designation issues.
1. English phrases typed as 'symbol' → change to 'expression'
2. Shorthand notation (Qe; W; U; Q) → stem:[Q_e] (take first/preferred)
3. Partial stem (S(stem:[lambda])) → stem:[S(lambda)]
"""
import yaml, glob, re

def is_english_phrase(text):
    """True if the designation is a readable English phrase, not a symbol."""
    text = text.strip()
    if not text:
        return False
    # All lowercase letters and spaces (no math notation)
    if re.match(r'^[a-z][a-z\s\-]+$', text):
        return True
    # Starts with lowercase, contains spaces, no semicolons or math ops
    if re.match(r'^[a-z].* ', text) and ';' not in text and not any(c in text for c in '_{}^[]'):
        return True
    return False

def fix_shorthand_symbol(text):
    """Convert shorthand like 'Qe; W; U; Q' to stem:[Q_e]."""
    text = text.strip()
    # Already has stem — try to consolidate
    if 'stem:[' in text:
        # S(stem:[lambda]) → stem:[S(lambda)]
        text = re.sub(r'(\w)\(stem:\[([^\]]*)\]\)', lambda m: f'stem:[{m.group(1)}({m.group(2)})]', text)
        # stem:[L],stem:[lambda] → stem:[L(lambda)] (merge adjacent)
        text = re.sub(r'stem:\[([^\]]*)\],stem:\[([^\]]*)\]', lambda m: f'stem:[{m.group(1)}({m.group(2)})]', text)
        return text

    # Shorthand with semicolons: take first form
    if ';' in text:
        first = text.split(';')[0].strip()
    else:
        first = text

    # Convert variable+subscript: Qe → Q_e, Ev → E_v, Le → L_e
    m = re.match(r'^([A-Z])([a-z])$', first)
    if m:
        return f'stem:[{m.group(1)}_{m.group(2)}]'

    # Variable,subscript: Le,lambda → L_(e,lambda)
    m = re.match(r'^([A-Z])([a-z]),([a-z]+)$', first)
    if m:
        return f'stem:[{m.group(1)}_({m.group(2)},{m.group(3)})]'

    # Single letter
    if re.match(r'^[A-Z]$', first):
        return f'stem:[{first}]'

    # Two-letter uppercase (like sr — unit, not symbol)
    if re.match(r'^[a-z]{2}$', first):
        return first  # Keep as-is (unit abbreviation)

    # Variable with comma-separated subscripts: Ev,v → E_(v,v)
    m = re.match(r'^([A-Z])([a-z]),([a-z])$', first)
    if m:
        return f'stem:[{m.group(1)}_({m.group(2)},{m.group(3)})]'

    return text

def process_file(path):
    raw = open(path).read()
    try:
        docs = list(yaml.safe_load_all(raw))
    except:
        return False

    changed = False
    for doc in docs:
        if not doc or not isinstance(doc, dict):
            continue
        data = doc.get('data')
        if not data or not isinstance(data, dict):
            continue

        terms = data.get('terms')
        if not terms or not isinstance(terms, list):
            continue

        for t in terms:
            if not isinstance(t, dict):
                continue
            dtype = t.get('type', '')
            desig = t.get('designation', '')

            if dtype != 'symbol':
                continue
            if not desig or desig.startswith('stem:['):
                continue

            original = desig

            # English phrase → expression
            if is_english_phrase(desig):
                t['type'] = 'expression'
                changed = True
                continue

            # Shorthand → stem:[]
            fixed = fix_shorthand_symbol(desig)
            if fixed != original:
                t['designation'] = fixed
                changed = True

    if not changed:
        return False

    output = yaml.safe_dump_all(docs, default_flow_style=False, allow_unicode=True,
                                 sort_keys=False, width=10000)
    open(path, 'w').write(output)
    return True

total = fixed = 0
for d in ['datasets/cie-2020/concepts', 'datasets/cie-2011/concepts']:
    for f in sorted(glob.glob(f'{d}/*.yaml')):
        total += 1
        if process_file(f):
            fixed += 1

print(f'Processed: {total}, Fixed: {fixed}')
