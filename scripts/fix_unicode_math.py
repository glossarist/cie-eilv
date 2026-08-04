#!/usr/bin/env python3
"""Round 4: Fix ALL remaining fake-math Unicode and HTML entities."""
import yaml, glob, re, html

GREEK_MAP = {
    'α': 'alpha', 'β': 'beta', 'γ': 'gamma', 'δ': 'delta', 'ε': 'epsilon',
    'ζ': 'zeta', 'η': 'eta', 'θ': 'theta', 'ι': 'iota', 'κ': 'kappa',
    'λ': 'lambda', 'μ': 'mu', 'ν': 'nu', 'ξ': 'xi', 'π': 'pi',
    'ρ': 'rho', 'σ': 'sigma', 'τ': 'tau', 'υ': 'upsilon', 'φ': 'phi',
    'χ': 'chi', 'ψ': 'psi', 'ω': 'omega',
    'Α': 'Alpha', 'Β': 'Beta', 'Γ': 'Gamma', 'Δ': 'Delta', 'Ε': 'Epsilon',
    'Ζ': 'Zeta', 'Η': 'Eta', 'Θ': 'Theta', 'Ι': 'Iota', 'Κ': 'Kappa',
    'Λ': 'Lambda', 'Μ': 'Mu', 'Ν': 'Nu', 'Ξ': 'Xi', 'Ο': 'Omicron',
    'Π': 'Pi', 'Ρ': 'Rho', 'Σ': 'Sigma', 'Τ': 'Tau', 'Υ': 'Upsilon',
    'Φ': 'Phi', 'Χ': 'Chi', 'Ψ': 'Psi', 'Ω': 'Omega',
}

OP_MAP = {
    '×': ' xx ', '÷': ' div ', '·': ' cdot ', '⋅': ' cdot ',
    '≈': ' ~~ ', '≠': ' != ', '≤': ' <= ', '≥': ' >= ',
    '±': ' +- ', '∓': ' -+ ', '≡': ' -= ', '∝': ' prop ',
    '∞': ' oo ', '∂': ' del ', '∇': ' grad ', '√': ' sqrt ',
    '→': ' -> ', '←': ' <- ', '↔': ' <-> ',
    '∪': ' uu ', '∩': ' nn ', '∈': ' in ',
    '∘': ' @ ', '⊙': ' o. ', '⊕': ' o+ ',
    '⊥': ' _|_ ', '∠': ' /_\\ ',
    '′': "'", '″': "''",
}

STEM_RE = re.compile(r'(?:\*?stem|\*?latexmath):\[[^\]]*\]')

def fix_text(text):
    if not text or not isinstance(text, str):
        return text

    # 1. Decode ALL HTML entities everywhere
    text = html.unescape(text)

    # 2. Unicode minus → regular hyphen (always)
    text = text.replace('−', '-')

    # 3. Unicode primes → ASCII apostrophe
    text = text.replace('′', "'").replace('″', "''")

    # Now protect stem blocks and links, fix the rest
    segments = re.split(r'((?:\*?stem|\*?latexmath):\[[^\]]*\]|\{\{[^}]+\}\}|<<[^>]+>>)', text)
    result = []
    for seg in segments:
        if re.match(r'(?:\*?stem|\*?latexmath):\[', seg) or seg.startswith('{{') or seg.startswith('<<'):
            result.append(seg)
            continue

        # 4. Greek letters outside stem:[]
        for greek, name in GREEK_MAP.items():
            seg = seg.replace(greek, f'stem:[{name}]')

        # 5. Math operators outside stem:[]
        for op, replacement in OP_MAP.items():
            if op in seg:
                seg = seg.replace(op, replacement)

        # 6. Unicode fractions
        fracs = {'½': '1/2', '⅓': '1/3', '⅔': '2/3', '¼': '1/4', '¾': '3/4',
                 '⅕': '1/5', '⅖': '2/5', '⅗': '3/5', '⅘': '4/5'}
        for u, a in fracs.items():
            seg = seg.replace(u, a)

        # 7. Degree sign — keep as ° in prose (temperature, angle text)
        # but convert to stem:[deg] when adjacent to numbers in math context
        # Actually, just keep ° as-is for readability in prose

        result.append(seg)

    return ''.join(result)


def fix_designation(text):
    if not text:
        return text
    text = html.unescape(text)
    text = text.replace('−', '-')
    text = text.replace('′', "'")

    # Greek in designation
    segments = re.split(r'((?:\*?stem|\*?latexmath):\[[^\]]*\])', text)
    result = []
    for seg in segments:
        if seg.startswith('stem:[') or seg.startswith('*stem:['):
            result.append(seg)
            continue
        for greek, name in GREEK_MAP.items():
            seg = seg.replace(greek, f'stem:[{name}]')
        for op, repl in OP_MAP.items():
            if op in seg:
                seg = seg.replace(op, repl.strip())
        result.append(seg)
    return ''.join(result)


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

        for field in ['definition', 'notes', 'examples']:
            for entry in (data.get(field) or []):
                if isinstance(entry, dict):
                    original = entry.get('content', '')
                    fixed = fix_text(original)
                    if fixed != original:
                        entry['content'] = fixed
                        changed = True

        for t in (data.get('terms') or []):
            if isinstance(t, dict):
                original = t.get('designation', '')
                fixed = fix_designation(original)
                if fixed != original:
                    t['designation'] = fixed
                    changed = True

    if not changed:
        return False
    output = yaml.safe_dump_all(docs, default_flow_style=False, allow_unicode=True, sort_keys=False, width=10000)
    open(path, 'w').write(output)
    return True


fixed = 0
for d in ['datasets/cie-2020/concepts', 'datasets/cie-2011/concepts']:
    for f in sorted(glob.glob(f'{d}/*.yaml')):
        if process_file(f):
            fixed += 1
print(f'Fixed: {fixed}')
