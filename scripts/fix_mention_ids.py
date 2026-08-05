#!/usr/bin/env python3
"""
Fix mention encoding gaps:
1. Add IEV: prefix to ConceptSource IDs (so cite keys match)
2. Convert bare CIE 2011 references to {{cite:cie-2011:NNN, NNN}} mentions
3. Add matching ConceptSource entries for CIE 2011 references
"""
import yaml, glob, re, os

CIE_2011_NOTE_RE = re.compile(r'numbered\s+(17-\d+)\s+in CIE S 017:2011', re.IGNORECASE)

def fix_source_ids(docs):
    """Add IEV: prefix to ConceptSource ids where source is IEV."""
    changed = False
    for doc in docs:
        if not doc or not isinstance(doc, dict): continue
        data = doc.get('data')
        if not isinstance(data, dict): continue
        sources = data.get('sources')
        if not isinstance(sources, list): continue
        for s in sources:
            if not isinstance(s, dict): continue
            sid = s.get('id', '')
            ref = s.get('origin', {}).get('ref', {})
            source = ref.get('source', '')
            if source == 'IEV' and sid and not sid.startswith('IEV:'):
                s['id'] = f'IEV:{sid}'
                changed = True
        # Also fix top-level sources on managed concept
        for s in (doc.get('sources') or []):
            if not isinstance(s, dict): continue
            sid = s.get('id', '')
            ref = s.get('origin', {}).get('ref', {})
            source = ref.get('source', '')
            if source == 'IEV' and sid and not sid.startswith('IEV:'):
                s['id'] = f'IEV:{sid}'
                changed = True
    return changed

def fix_cie_2011_notes(docs, termid):
    """Convert bare '17-NNN in CIE S 017:2011' to cite mentions + add sources."""
    changed = False
    new_source_ids = set()

    for doc in docs:
        if not doc or not isinstance(doc, dict): continue
        data = doc.get('data')
        if not isinstance(data, dict): continue
        notes = data.get('notes')
        if not isinstance(notes, list): continue

        for n in notes:
            if not isinstance(n, dict): continue
            content = n.get('content', '')
            if not content: continue

            def replace_ref(m):
                old_id = m.group(1)
                new_id = f'cie-2011:{old_id}'
                new_source_ids.add((new_id, old_id))
                return f'numbered {{{{cite:{new_id}, {old_id}}}}} in CIE S 017:2011'

            new_content = CIE_2011_NOTE_RE.sub(replace_ref, content)
            if new_content != content:
                n['content'] = new_content
                changed = True

    # Add ConceptSource entries for new cite refs
    if new_source_ids:
        for doc in docs:
            if not doc or not isinstance(doc, dict): continue
            data = doc.get('data')
            if not isinstance(data, dict): continue
            # Only add to localized concept docs (those with 'definition')
            if 'definition' not in data: continue
            sources = data.get('sources')
            if not isinstance(sources, list):
                sources = []
                data['sources'] = sources

            existing_ids = {s.get('id') for s in sources if isinstance(s, dict)}
            for source_id, old_id in new_source_ids:
                if source_id not in existing_ids:
                    sources.append({
                        'id': source_id,
                        'type': 'authoritative',
                        'origin': {
                            'ref': {
                                'source': 'CIE S 017:2011',
                                'id': old_id,
                            }
                        }
                    })
                    changed = True
            break  # Only add to first localized concept

    return changed

def process_file(path):
    try:
        docs = list(yaml.safe_load_all(open(path)))
    except:
        return False

    changed = False
    changed |= fix_source_ids(docs)

    termid = os.path.basename(path).replace('.yaml', '')
    changed |= fix_cie_2011_notes(docs, termid)

    if not changed:
        return False

    output = yaml.safe_dump_all(docs, default_flow_style=False, allow_unicode=True,
                                 sort_keys=False, width=10000)
    open(path, 'w').write(output)
    return True

fixed = 0
for d in ['datasets/cie-2020/concepts', 'datasets/cie-2011/concepts']:
    for f in sorted(glob.glob(f'{d}/*.yaml')):
        if process_file(f):
            fixed += 1

print(f'Fixed: {fixed} files')
