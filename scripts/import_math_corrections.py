#!/usr/bin/env python3
"""
Import editor-verified math corrections from issue #6 into cie-2020
and backfill cie-2011 via superseded_by relationships.

Usage:
  python3 scripts/import_math_corrections.py /tmp/corrections-merged.json
"""
import yaml, glob, json, re, os, sys

STEM_RE = re.compile(r'((?:\*?stem|\*?latexmath):\[[^\]]*\])')
GIF_NUM_RE = re.compile(r'mml_m(\d+)')

GREEK_FIX = {'λ': 'lambda', 'Φ': 'Phi', 'ν': 'nu', 'σ': 'sigma',
             'β': 'beta', 'μ': 'mu', 'ρ': 'rho', 'τ': 'tau',
             'α': 'alpha', 'δ': 'delta', 'ε': 'epsilon', 'θ': 'theta',
             'Δ': 'Delta', 'Ω': 'Omega', 'π': 'pi'}


def clean_expression(expr):
    """Replace any remaining Unicode Greek with ASCII names."""
    for greek, name in GREEK_FIX.items():
        expr = expr.replace(greek, name)
    return expr


def load_corrections(path):
    data = json.load(open(path))
    # Clean Unicode
    for e in data:
        e['expression'] = clean_expression(e['expression'])
    # Group by (termid, location)
    grouped = {}
    for e in data:
        key = (e['termid'], e['location'])
        grouped.setdefault(key, []).append(e)
    # Sort each group by GIF number
    for key, entries in grouped.items():
        entries.sort(key=lambda e: int(GIF_NUM_RE.search(e['gif']).group(1)))
    return grouped


def replace_stems_in_content(content, expressions):
    """Replace all stem:[...] blocks in content with the given expressions.
    Preserves surrounding prose."""
    if not expressions:
        return content

    # For designation: replace the entire designation value
    # For definition/notes: replace stem blocks positionally
    parts = STEM_RE.split(content)
    # parts alternates: [text, stem, text, stem, text, ...]
    # We replace the stem parts with our expressions
    result = []
    expr_idx = 0
    for i, part in enumerate(parts):
        if i % 2 == 1:  # This is a stem block
            if expr_idx < len(expressions):
                result.append(f"stem:[{expressions[expr_idx]['expression']}]")
                expr_idx += 1
            else:
                result.append(part)  # Keep existing if we run out of corrections
        else:
            result.append(part)

    # If we have more expressions than stem blocks, append them
    while expr_idx < len(expressions):
        result.append(f"\n\nstem:[{expressions[expr_idx]['expression']}]")
        expr_idx += 1

    return ''.join(result)


def apply_to_concept(yaml_path, grouped_corrections, termid):
    """Apply corrections to a single concept file."""
    docs = list(yaml.safe_load_all(open(yaml_path)))
    changed = False

    for doc in docs:
        if not doc or not isinstance(doc, dict):
            continue
        data = doc.get('data')
        if not data or not isinstance(data, dict):
            continue

        # Designation corrections
        key = (termid, 'designation')
        if key in grouped_corrections:
            expressions = grouped_corrections[key]
            terms = data.get('terms') or []
            sym_idx = 0
            for t in terms:
                if not isinstance(t, dict):
                    continue
                if t.get('type') in ('symbol', 'letter_symbol'):
                    if sym_idx < len(expressions):
                        t['designation'] = f"stem:[{expressions[sym_idx]['expression']}]"
                        sym_idx += 1
                        changed = True

        # Definition corrections
        key = (termid, 'definition')
        if key in grouped_corrections:
            expressions = grouped_corrections[key]
            for d in (data.get('definition') or []):
                if isinstance(d, dict):
                    original = d.get('content', '')
                    fixed = replace_stems_in_content(original, expressions)
                    if fixed != original:
                        d['content'] = fixed
                        changed = True

        # Note corrections
        for loc_key, entries in grouped_corrections.items():
            t, location = loc_key
            if t != termid or not location.startswith('note-'):
                continue
            note_idx = int(location.split('-')[1])
            notes = data.get('notes') or []
            if note_idx < len(notes):
                n = notes[note_idx]
                if isinstance(n, dict):
                    original = n.get('content', '')
                    fixed = replace_stems_in_content(original, entries)
                    if fixed != original:
                        n['content'] = fixed
                        changed = True

    if changed:
        output = yaml.safe_dump_all(docs, default_flow_style=False,
                                     allow_unicode=True, sort_keys=False, width=10000)
        open(yaml_path, 'w').write(output)
    return changed


def find_2011_concepts_for(termid):
    """Find cie-2011 concept IDs that are superseded by the given 2020 concept."""
    ids = set()
    # Check 2011 concepts for superseded_by → this termid
    for f in glob.glob('datasets/cie-2011/concepts/*.yaml'):
        try:
            for doc in yaml.safe_load_all(open(f)):
                if not doc: continue
                related = doc.get('related') or []
                for rel in related:
                    if isinstance(rel, dict) and 'supersed' in str(rel.get('type', '')):
                        ref = rel.get('ref', {})
                        if ref.get('id') == termid:
                            # This 2011 concept is superseded by our 2020 concept
                            data = doc.get('data', {})
                            if isinstance(data, dict):
                                ids.add(data.get('identifier', ''))
        except:
            pass
    return ids


def main():
    corr_path = sys.argv[1] if len(sys.argv) > 1 else '/tmp/corrections-merged.json'
    grouped = load_corrections(corr_path)

    # ── cie-2020 ──────────────────────────────────────────────
    fixed_2020 = 0
    concept_ids = set()
    for (termid, location), entries in grouped.items():
        concept_ids.add(termid)

    for termid in sorted(concept_ids):
        path = f'datasets/cie-2020/concepts/{termid}.yaml'
        if os.path.exists(path):
            if apply_to_concept(path, grouped, termid):
                fixed_2020 += 1

    print(f'cie-2020: {fixed_2020} concepts updated')

    # ── cie-2011 backfill ────────────────────────────────────
    # Build mapping: 2020 termid → set of 2011 IDs
    mapping = {}
    for termid in concept_ids:
        mapping[termid] = find_2011_concepts_for(termid)

    fixed_2011 = 0
    for termid, ids_2011 in mapping.items():
        for id_2011 in ids_2011:
            if not id_2011:
                continue
            path = f'datasets/cie-2011/concepts/{id_2011}.yaml'
            if os.path.exists(path):
                # Use the 2020 corrections but with 2011 termid for note matching
                corr_2011 = {}
                for (t, loc), entries in grouped.items():
                    if t == termid:
                        corr_2011[(id_2011, loc)] = entries
                if corr_2011 and apply_to_concept(path, corr_2011, id_2011):
                    fixed_2011 += 1

    print(f'cie-2011: {fixed_2011} concepts backfilled')


if __name__ == '__main__':
    main()
