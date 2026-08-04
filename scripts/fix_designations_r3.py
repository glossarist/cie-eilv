#!/usr/bin/env python3
"""Round 3: Fix remaining 104 symbol designation edge cases."""
import yaml, glob, re

# English phrases that should be expression, not symbol
ENGLISH_PHRASES = {
    "stiles–crawford effect of the first kind",
    "stiles-crawford effect of the first kind",
    "d illuminant",
    "ulbricht sphere",
    "napierian spectral internal transmittance density",
    "45°a geometry",
    "45°x geometry",
}

def fix_symbol_desig(desig):
    desig = desig.strip()
    if not desig or desig.startswith('stem:['):
        return desig

    low = desig.lower()

    # English phrase → expression
    if low in ENGLISH_PHRASES:
        return '__EXPRESSION__'

    # AsciiDoc subscripts ~x~ → stem:[..._x]
    if '~' in desig and '<' not in desig:
        m = re.match(r'^([A-Z])~([^~]+)~$', desig)
        if m:
            return f'stem:[{m.group(1)}_{m.group(2)}]'
        m = re.match(r'^([A-Z])~([^~]+),([^~]+)~$', desig)
        if m:
            return f'stem:[{m.group(1)}_({m.group(2)},{m.group(3)})]'

    # Leftover HTML + AsciiDoc mix: F</i>~SP~ → stem:[F_SP]
    if '</i>' in desig:
        cleaned = re.sub(r'</?i>', '', desig)
        cleaned = re.sub(r'~([^~]+)~', r'_\1', cleaned)
        if re.match(r'^[A-Z]_', cleaned):
            return f'stem:[{cleaned}]'

    # Delta prefix: ∆stem:[c] → stem:[Delta c]
    if desig.startswith('∆stem:[') or desig.startswith('Δstem:['):
        inner = re.search(r'stem:\[([^\]]*)\]', desig)
        if inner:
            return f'stem:[Delta {inner.group(1)}]'

    # Adjacent letter + stem: astem:[n(lambda)] → stem:[a(n)]
    m = re.match(r'^([a-z])stem:\[([^\]]*)\]$', desig)
    if m:
        return f'stem:[{m.group(1)}({m.group(2)})]'

    # Comma-separated with stem: Le,stem:[lambda],Lstem:[lambda] → stem:[L_(e,lambda)]
    m = re.match(r'^([A-Z])([a-z]),stem:\[([^\]]*)\]', desig)
    if m:
        return f'stem:[{m.group(1)}_({m.group(2)},{m.group(3)})]'

    # Semicolon-separated multi-form: take first
    if ';' in desig:
        first = desig.split(';')[0].strip().rstrip(',')
    else:
        first = desig

    # Remove usage info <...>
    first = re.sub(r'\s*<[^>]*>', '', first).strip()
    first = first.rstrip(',').strip()
    if not first:
        first = desig.split(';')[0].strip()

    # Variable + multi-char subscript: Heff → H_eff, Kcd → K_cd, Epb → E_pb
    m = re.match(r'^([A-Z])([a-z]{2,})$', first)
    if m:
        return f'stem:[{m.group(1)}_{m.group(2)}]'

    # Variable + single subscript: Ee → E_e, qe → q_e
    m = re.match(r'^([A-Za-z])([a-z])$', first)
    if m:
        return f'stem:[{m.group(1)}_{m.group(2)}]'

    # Variable,subscript: Ev,v → E_(v,v), Le,lambda → L_(e,lambda)
    m = re.match(r'^([A-Z])([a-z]),([a-z]+)$', first)
    if m:
        return f'stem:[{m.group(1)}_({m.group(2)},{m.group(3)})]'

    # Single lowercase letter: m, r, n, h, v → stem:[m] etc
    if re.match(r'^[a-z]$', first):
        return f'stem:[{first}]'

    # Single uppercase letter: G, K → stem:[G]
    if re.match(r'^[A-Z]$', first):
        return f'stem:[{first}]'

    # Uppercase + subscript digits: X10 → X_10
    m = re.match(r'^([A-Z])(\d+)$', first)
    if m:
        return f'stem:[{m.group(1)}_{m.group(2)}]'

    # Comma-separated variables: X, Y, Z → stem:[X, Y, Z]
    if re.match(r'^[A-Z](?:,\s*[A-Z])+$', first):
        return f'stem:[{first}]'

    # D* → stem:[D^*]
    if first == 'D*':
        return 'stem:[D^*]'

    # Heff,o → H_(eff,o)
    m = re.match(r'^([A-Z])([a-z]+),([a-z]+)$', first)
    if m:
        return f'stem:[{m.group(1)}_({m.group(2)},{m.group(3)})]'

    return desig

def process_file(path):
    raw = open(path).read()
    try:
        docs = list(yaml.safe_load_all(raw))
    except:
        return False

    changed = False
    for doc in docs:
        if not doc or not isinstance(doc, dict): continue
        data = doc.get('data')
        if not data or not isinstance(data, dict): continue
        terms = data.get('terms')
        if not terms or not isinstance(terms, list): continue

        for t in terms:
            if not isinstance(t, dict): continue
            if t.get('type') not in ('symbol', 'letter_symbol'): continue
            desig = t.get('designation', '')
            if not desig or desig.startswith('stem:['): continue

            fixed = fix_symbol_desig(desig)
            if fixed == '__EXPRESSION__':
                t['type'] = 'expression'
                changed = True
            elif fixed != desig:
                t['designation'] = fixed
                changed = True

    if not changed: return False
    output = yaml.safe_dump_all(docs, default_flow_style=False, allow_unicode=True, sort_keys=False, width=10000)
    open(path, 'w').write(output)
    return True

fixed = 0
for d in ['datasets/cie-2020/concepts', 'datasets/cie-2011/concepts']:
    for f in sorted(glob.glob(f'{d}/*.yaml')):
        if process_file(f):
            fixed += 1
print(f'Fixed: {fixed}')
