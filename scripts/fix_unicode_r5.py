#!/usr/bin/env python3
"""Round 5: Fix ALL remaining non-ASCII math characters.
Both OUTSIDE stem (convert to stem:[] or ASCII) and INSIDE stem
(convert Unicode Greek/operators to AsciiMath names)."""
import yaml, glob, re, unicodedata

GREEK_TO_ASCII = {
    'α': 'alpha', 'β': 'beta', 'γ': 'gamma', 'δ': 'delta', 'ε': 'epsilon',
    'ζ': 'zeta', 'η': 'eta', 'θ': 'theta', 'ι': 'iota', 'κ': 'kappa',
    'λ': 'lambda', 'μ': 'mu', 'ν': 'nu', 'ξ': 'xi', 'ο': 'omicron',
    'π': 'pi', 'ρ': 'rho', 'σ': 'sigma', 'τ': 'tau', 'υ': 'upsilon',
    'φ': 'phi', 'χ': 'chi', 'ψ': 'psi', 'ω': 'omega',
    'Α': 'Alpha', 'Β': 'Beta', 'Γ': 'Gamma', 'Δ': 'Delta', 'Ε': 'Epsilon',
    'Ζ': 'Zeta', 'Η': 'Eta', 'Θ': 'Theta', 'Ι': 'Iota', 'Κ': 'Kappa',
    'Λ': 'Lambda', 'Μ': 'Mu', 'Ν': 'Nu', 'Ξ': 'Xi', 'Ο': 'Omicron',
    'Π': 'Pi', 'Ρ': 'Rho', 'Σ': 'Sigma', 'Τ': 'Tau', 'Υ': 'Upsilon',
    'Φ': 'Phi', 'Χ': 'Chi', 'Ψ': 'Psi', 'Ω': 'Omega',
    'ϑ': 'theta', 'ϕ': 'phi', '∆': 'Delta',
}

OP_TO_ASCII = {
    '·': 'cdot', '⋅': 'cdot', '×': 'xx', '÷': 'div',
    '≈': '~~', '≤': '<=', '≥': '>=', '≠': '!=', '±': '+-',
    '≡': '-=', '∝': 'prop', '∞': 'oo', '∂': 'del', '∇': 'grad',
    '√': 'sqrt', '→': '->', '←': '<-', '°': 'deg',
    '∬': 'iint', '∮': 'oint', '∑': 'sum', '∫': 'int', '∏': 'prod',
    '∪': 'uu', '∩': 'nn', '∈': 'in', '∉': '!in',
    '∘': '@', '⊕': 'o+', '⊗': 'ox', '⊥': '_|_',
    '′': "'", '″': "''", '‴': "'''",
    '−': '-', '–': '-', '—': '-', '‑': '-',
    '∪': 'uu',
}

# Characters to just remove (zero-width)
INVISIBLE = {'​': '', '‌': '', '‍': '', '﻿': ''}

# Non-math typographic (keep as-is)
TYPOGRAPHIC = set('""''…—         ')

STEM_RE = re.compile(r'((?:\*?stem|\*?latexmath):\[[^\]]*\])')

def fix_inside_stem(text):
    """Fix Unicode inside stem:[] blocks — convert to AsciiMath names."""
    for greek, name in GREEK_TO_ASCII.items():
        text = text.replace(greek, name)
    for op, name in OP_TO_ASCII.items():
        text = text.replace(op, name)
    for inv, repl in INVISIBLE.items():
        text = text.replace(inv, repl)
    text = text.replace('\xa0', ' ')  # NBSP → space
    return text

def fix_outside_stem(text):
    """Fix Unicode outside stem:[] — wrap Greek/operators in stem:[]."""
    for greek, name in GREEK_TO_ASCII.items():
        text = text.replace(greek, f'stem:[{name}]')
    for op, name in OP_TO_ASCII.items():
        if op in text:
            text = text.replace(op, f'stem:[{name}]')
    for inv, repl in INVISIBLE.items():
        text = text.replace(inv, repl)
    text = text.replace('\xa0', ' ')  # NBSP → regular space
    text = text.replace('‑', '-')  # Non-breaking hyphen → hyphen
    return text

def fix_text(text):
    if not text or not isinstance(text, str):
        return text

    # Split on stem blocks and existing links
    segments = re.split(r'((?:\*?stem|\*?latexmath):\[[^\]]*\]|\{\{[^}]+\}\}|<<[^>]+>>)', text)
    result = []
    for seg in segments:
        if seg.startswith('stem:[') or seg.startswith('*stem:[') or seg.startswith('{{') or seg.startswith('<<'):
            # Fix inside stem blocks
            result.append(fix_inside_stem(seg))
        else:
            result.append(fix_outside_stem(seg))
    return ''.join(result)

def fix_designation(text):
    if not text:
        return text
    # For designations, convert Unicode to stem:[] (same as outside stem)
    return fix_outside_stem(text)

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
