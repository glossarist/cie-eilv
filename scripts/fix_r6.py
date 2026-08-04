#!/usr/bin/env python3
"""Round 6: Fix bare cdot outside stem, AsciiDoc superscripts in math context,
HTML entities (&equals;), and image-map cruft."""
import yaml, glob, re

STEM_RE = re.compile(r'(?:\*?stem|\*?latexmath):\[[^\]]*\]')

def fix_text(text):
    if not text or not isinstance(text, str):
        return text

    # 1. Decode &equals; → =
    text = text.replace('&equals;', '=')

    # 2. Remove <map>/<area> image-map cruft
    text = re.sub(r'<map[^>]*>.*?</map>', '', text, flags=re.DOTALL)

    # 3. Fix bare 'cdot' outside stem (from round 1 operator conversion)
    # Pattern: Wcdotnm^-1^ → stem:[W cdot nm^(-1)]
    # These are unit expressions where cdot and ^ are mixed

    # Split on stem blocks to only fix outside
    segments = re.split(r'((?:\*?stem|\*?latexmath):\[[^\]]*\]|\{\{[^}]+\}\}|<<[^>]+>>)', text)
    result = []
    for seg in segments:
        if seg.startswith('stem:[') or seg.startswith('*stem:[') or seg.startswith('{{') or seg.startswith('<<'):
            result.append(seg)
            continue

        # Fix unit expressions with cdot and/or ^...^ superscripts
        # Pattern: (Wcdotnm^-1^) or (lmcdotm^-2^) or (m^-1^)
        seg = fix_unit_expr(seg)
        result.append(seg)

    return ''.join(result)

def fix_unit_expr(seg):
    """Convert unit expressions with cdot/^ outside stem to stem:[]"""
    # Pattern: parenthesized unit expression with cdot or ^...^
    def convert_unit(m):
        inner = m.group(1)
        # Only convert if it has cdot or ^...^
        if 'cdot' not in inner and '^' not in inner:
            return m.group(0)

        # Convert AsciiDoc ^...^ to ^(...)
        converted = re.sub(r'\^([^^\s]+)\^', r'^(\1)', inner)
        # Convert bare cdot to ' cdot '
        converted = re.sub(r'(\w)cdot', r'\1 cdot ', converted)
        converted = re.sub(r'cdot(\w)', r' cdot \1', converted)
        # Clean up double spaces
        converted = re.sub(r'\s+', ' ', converted).strip()

        return f'stem:[{converted}]'

    # Match parenthesized expressions like (Wcdotnm^-1^)
    seg = re.sub(r'\(([^()]*?(?:cdot|\^[^\s]+\^)[^()]*?)\)', convert_unit, seg)

    # Also handle bare cdot not in parens: "Wcdotm^-2^" without parens
    if 'cdot' in seg and 'stem:[' not in seg:
        seg = re.sub(r'\^([^\s]+)\^', r'^(\1)', seg)
        seg = re.sub(r'(\w)cdot', r'\1 cdot ', seg)
        seg = re.sub(r'cdot(\w)', r' cdot \1', seg)
        seg = re.sub(r'\s+', ' ', seg).strip()

    return seg


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
