#!/usr/bin/env python3
"""
Direct math text fixer — transforms improperly encoded math across
both cie-2020 and cie-2011 datasets.

Handles:
1. HTML tags: <i>X</i> → stem:[X], <i>X</i><sub>Y</sub> → stem:[X_Y]
2. Bare Greek letters outside stem:[] → stem:[name]
3. Bare operators (·×≈≤≥±) → stem:[] equivalents
4. Unicode super/subscripts → AsciiDoc notation
5. Symbol designations → stem:[] notation
6. Plain-text math expressions → stem:[]
"""

import yaml, glob, re, os, sys

# ── Greek letter mapping ──────────────────────────────────────────────
GREEK_MAP = {
    'λ': 'lambda', 'Λ': 'Lambda', 'Φ': 'Phi', 'φ': 'phi',
    'ν': 'nu', 'Ν': 'Nu', 'σ': 'sigma', 'Σ': 'Sigma',
    'β': 'beta', 'Β': 'Beta', 'Θ': 'Theta', 'θ': 'theta',
    'μ': 'mu', 'Μ': 'Mu', 'Δ': 'Delta', 'δ': 'delta',
    'α': 'alpha', 'Α': 'Alpha', 'γ': 'gamma', 'Γ': 'Gamma',
    'ε': 'epsilon', 'ρ': 'rho', 'τ': 'tau', 'ω': 'omega',
    'Ω': 'Omega', 'π': 'pi', 'Π': 'Pi', 'χ': 'chi',
    'ψ': 'psi', 'Ψ': 'Psi', 'ξ': 'xi', 'ζ': 'zeta',
    'η': 'eta', 'κ': 'kappa', 'ι': 'iota', 'υ': 'upsilon',
}

# ── Operator mapping ──────────────────────────────────────────────────
OP_MAP = {
    '·': ' cdot ', '×': ' xx ', '÷': ' div ',
    '≈': ' ~~ ', '≤': ' <= ', '≥': ' >= ',
    '±': ' +- ', '≠': ' != ', '≡': ' -= ',
    '∘': ' @ ', '∂': ' del ', '∞': ' oo ',
    '→': ' -> ', '←': ' <- ', '↔': ' <-> ',
}

# ── Unicode super/subscript mapping ───────────────────────────────────
SUPER_MAP = str.maketrans('⁰¹²³⁴⁵⁶⁷⁸⁹⁻⁺', '0123456789-+')
SUB_MAP = str.maketrans('ₐₑᵢₒᵤₓ₀₁₂₃₄₅₆₇₈₉', 'aeioux0123456789')

STEM_RE = re.compile(r'(?:\*?stem|\*?latexmath):\[[^\]]*\]')
EXISTING_LINK_RE = re.compile(r'(\{\{[^}]+\}\}|<<[^>]+>>)')


def fix_html_math(text):
    """Convert HTML math tags to stem:[] or AsciiDoc notation."""
    if not text:
        return text

    # <i>X</i><sub>Y</sub> → stem:[X_Y]  (nested)
    text = re.sub(r'<i>([^<]*)</i><sub>([^<]*)</sub>', lambda m: f'stem:[{m.group(1)}_{m.group(2)}]', text)
    # <i>X</i><sup>Y</sup> → stem:[X^Y]
    text = re.sub(r'<i>([^<]*)</i><sup>([^<]*)</sup>', lambda m: f'stem:[{m.group(1)}^({m.group(2)})]', text)
    # <i><sub>Y</sub></i> → ~Y~
    text = re.sub(r'<i><sub>([^<]*)</sub></i>', lambda m: f'~{m.group(1)}~', text)
    # <i><sup>Y</sup></i> → ^Y^
    text = re.sub(r'<i><sup>([^<]*)</sup></i>', lambda m: f'^{m.group(1)}^', text)
    # <i>X</i> → stem:[X]
    text = re.sub(r'<i>([^<]*)</i>', lambda m: f'stem:[{m.group(1)}]', text)
    # <italic>X</italic> → stem:[X]
    text = re.sub(r'<italic>([^<]*)</italic>', lambda m: f'stem:[{m.group(1)}]', text)
    # <sub>Y</sub> → ~Y~
    text = re.sub(r'<sub>([^<]*)</sub>', lambda m: f'~{m.group(1)}~', text)
    # <sup>Y</sup> → ^Y^
    text = re.sub(r'<sup>([^<]*)</sup>', lambda m: f'^{m.group(1)}^', text)

    return text


def fix_bare_math(text):
    """Fix bare Greek letters, operators, and subscripts outside stem:[]."""
    if not text:
        return text

    # Split on stem blocks and existing links — only transform non-protected segments
    segments = re.split(r'((?:\*?stem|\*?latexmath):\[[^\]]*\]|\{\{[^}]+\}\}|<<[^>]+>>)', text)
    result = []
    for seg in segments:
        if re.match(r'(?:\*?stem|\*?latexmath):\[', seg) or seg.startswith('{{') or seg.startswith('<<'):
            result.append(seg)
            continue

        # Greek letters
        for greek, name in GREEK_MAP.items():
            seg = seg.replace(greek, f'stem:[{name}]')

        # Operators
        for op, replacement in OP_MAP.items():
            if op in seg:
                seg = seg.replace(op, replacement.strip())

        # Unicode superscripts/subscripts
        seg = re.sub(r'[⁰¹²³⁴⁵⁶⁷⁸⁹⁻⁺]+', lambda m: f'^{m.group().translate(SUPER_MAP)}^', seg)
        seg = re.sub(r'[ₐₑᵢₒᵤₓₔ₀₁₂₃₄₅₆₇₈₉]+', lambda m: f'~{m.group().translate(SUB_MAP)}~', seg)

        result.append(seg)

    return ''.join(result)


def fix_designation(text):
    """Fix symbol designations to use stem:[] notation."""
    if not text or text.startswith('stem:['):
        return text

    # Skip abbreviations (all-caps)
    if re.match(r'^[A-Z][A-Z0-9-]+$', text):
        return text

    # Skip plain English words
    if re.match(r'^[a-z][a-z\s-]+$', text) and not any(c in text for c in '₀₁₂₃₄₅₆₇₈₉⁰¹²³⁴⁵⁶⁷⁸⁹'):
        return text

    # Convert HTML in designation
    text = fix_html_math(text)

    # If it still has plain text math variables (single letters with subscripts)
    # like "Ev,v" or "Qe" → stem:[E_(v,v)] or stem:[Q_e]
    text = fix_bare_math(text)

    return text


def fix_content(text):
    """Apply all math fixes to a content string."""
    if not text or not isinstance(text, str):
        return text
    text = fix_html_math(text)
    text = fix_bare_math(text)
    return text


def process_file(path):
    """Process a single concept YAML file. Returns True if changed."""
    raw = open(path).read()
    try:
        docs = list(yaml.safe_load_all(raw))
    except yaml.YAMLError:
        return False

    changed = False

    for doc in docs:
        if not doc or not isinstance(doc, dict):
            continue
        data = doc.get('data')
        if not data or not isinstance(data, dict):
            continue

        # Fix definition content
        for d in (data.get('definition') or []):
            if isinstance(d, dict):
                original = d.get('content', '')
                fixed = fix_content(original)
                if fixed != original:
                    d['content'] = fixed
                    changed = True

        # Fix notes
        for n in (data.get('notes') or []):
            if isinstance(n, dict):
                original = n.get('content', '')
                fixed = fix_content(original)
                if fixed != original:
                    n['content'] = fixed
                    changed = True

        # Fix examples
        for e in (data.get('examples') or []):
            if isinstance(e, dict):
                original = e.get('content', '')
                fixed = fix_content(original)
                if fixed != original:
                    e['content'] = fixed
                    changed = True

        # Fix symbol designations
        for t in (data.get('terms') or []):
            if isinstance(t, dict):
                dtype = t.get('type', '')
                if dtype in ('symbol', 'letter_symbol'):
                    original = t.get('designation', '')
                    fixed = fix_designation(original)
                    if fixed != original:
                        t['designation'] = fixed
                        changed = True

    if not changed:
        return False

    # Write back preserving multi-doc format
    output = yaml.safe_dump_all(docs, default_flow_style=False, allow_unicode=True,
                                 sort_keys=False, width=10000)
    open(path, 'w').write(output)
    return True


def main():
    dirs = ['datasets/cie-2020/concepts', 'datasets/cie-2011/concepts']
    total = 0
    fixed = 0

    for d in dirs:
        files = sorted(glob.glob(f'{d}/*.yaml'))
        for f in files:
            total += 1
            if process_file(f):
                fixed += 1

    print(f'Processed: {total} files')
    print(f'Fixed: {fixed} files')


if __name__ == '__main__':
    main()
