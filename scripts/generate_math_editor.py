#!/usr/bin/env python3
"""Generate an interactive math correction editor for CIE e-ILV concepts."""

import base64, glob, json, os, re, yaml

PAGES_DIR = "reference-docs/scraped/terms/pages"
GIF_DIR = "reference-docs/math-gifs"
CONCEPTS_DIR = "datasets/cie-2020/concepts"
PLURIMATH_BUNDLE = "scripts/math-editor/plurimath-bundle.js"
OUT_PATH = "reference-docs/reports/math-editor.html"

HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Math Correction Editor — CIE e-ILV</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: system-ui, sans-serif; margin: 0; background: #f5f5f5; }
  .toolbar { position: sticky; top: 0; z-index: 100; background: #004ebc; color: white;
             padding: 0.75rem 1.5rem; display: flex; align-items: center; gap: 1rem;
             box-shadow: 0 2px 8px rgba(0,0,0,0.15); }
  .toolbar h1 { font-size: 1.1rem; margin: 0; flex: 1; }
  .toolbar button { background: white; color: #004ebc; border: none; padding: 0.5rem 1rem;
                    border-radius: 4px; font-weight: 600; cursor: pointer; font-size: 0.85rem; }
  .toolbar button:hover { background: #e0e8f0; }
  .toolbar .count { font-size: 0.8rem; opacity: 0.8; }
  .filter-bar { background: white; padding: 0.5rem 1.5rem; border-bottom: 1px solid #ddd;
                display: flex; gap: 1rem; align-items: center; font-size: 0.85rem; flex-wrap: wrap; }
  .filter-bar input, .filter-bar select { padding: 0.3rem 0.5rem; border: 1px solid #ccc; border-radius: 3px; }
  .entries { max-width: 1400px; margin: 0 auto; padding: 1rem; }
  .entry { background: white; border-radius: 8px; margin-bottom: 1rem; overflow: hidden;
           box-shadow: 0 1px 3px rgba(0,0,0,0.08); border-left: 4px solid #004ebc; }
  .entry.designation { border-left-color: #e29500; }
  .entry.corrected { border-left-color: #10b981; }
  .entry-header { padding: 0.5rem 1rem; background: #f8f9fa; border-bottom: 1px solid #eee;
                  display: flex; align-items: center; gap: 0.75rem; font-size: 0.85rem; flex-wrap: wrap; }
  .entry-header .termid { font-weight: 700; color: #004ebc; font-family: monospace; }
  .entry-header .location { background: #e9ecef; padding: 0.15rem 0.5rem; border-radius: 3px; font-size: 0.75rem; }
  .entry-header .location.designation { background: #fff3cd; }
  .entry-header .kind { color: #666; font-style: italic; }
  .entry-header .gif-name { color: #888; font-family: monospace; font-size: 0.75rem; margin-left: auto; }
  .entry-body { display: grid; grid-template-columns: 200px 1fr 1fr; gap: 1rem; padding: 1rem; }
  @media (max-width: 768px) { .entry-body { grid-template-columns: 1fr; } }
  .col-title { font-size: 0.7rem; text-transform: uppercase; color: #888; font-weight: 600; margin-bottom: 0.25rem; }
  .gif-cell img { max-width: 100%; max-height: 120px; image-rendering: pixelated; }
  .edit-cell textarea { width: 100%; min-height: 60px; font-family: monospace; font-size: 0.85rem;
                         padding: 0.5rem; border: 1px solid #ddd; border-radius: 4px; resize: vertical; }
  .edit-cell textarea:focus { outline: none; border-color: #004ebc; box-shadow: 0 0 0 2px rgba(0,78,188,0.15); }
  .render-cell { min-height: 60px; padding: 0.5rem; background: #fafafa; border: 1px solid #eee;
                  border-radius: 4px; overflow-x: auto; font-size: 1.1rem; }
  .render-cell math { font-size: 1.3rem; }
  .entry-actions { padding: 0.5rem 1rem; border-top: 1px solid #eee; display: flex; gap: 0.5rem; }
  .entry-actions button { padding: 0.25rem 0.75rem; border: 1px solid #ccc; background: white;
                           border-radius: 3px; cursor: pointer; font-size: 0.8rem; }
  .entry-actions button.save { background: #10b981; color: white; border-color: #10b981; }
  .entry-actions button.reset { color: #666; }
  .status { font-size: 0.75rem; color: #888; padding: 0 1rem 0.5rem; }
  .status.saved { color: #10b981; font-weight: 600; }
  .context { font-size: 0.75rem; color: #666; padding: 0 1rem 0.5rem; font-style: italic;
             border-bottom: 1px solid #f0f0f0; padding-bottom: 0.5rem; }
  #loading-overlay { position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(255,255,255,0.9);
                      z-index: 999; display: flex; align-items: center; justify-content: center;
                      font-size: 1.2rem; color: #004ebc; }
  #loading-overlay.hidden { display: none; }
</style>
</head>
<body>
<div id="loading-overlay">Loading Plurimath engine...</div>
<div class="toolbar">
  <h1>Math Correction Editor — CIE e-ILV</h1>
  <span class="count" id="stats"></span>
  <input type="file" id="import-file" accept=".json" style="display:none" onchange="importJSON(this)">
  <button onclick="document.getElementById('import-file').click()">Import JSON</button>
  <button onclick="exportJSON()">Export JSON</button>
  <button onclick="saveAll()">Save All</button>
</div>
<div class="filter-bar">
  <input type="text" id="filter" placeholder="Filter by termid..." oninput="applyFilter()" style="width:200px">
  <select id="kind-filter" onchange="applyFilter()">
    <option value="">All types</option>
    <option value="designation-symbol">Designation symbols</option>
    <option value="equation">Equations</option>
  </select>
  <select id="status-filter" onchange="applyFilter()">
    <option value="">All</option>
    <option value="unsaved">Unsaved</option>
    <option value="saved">Saved</option>
  </select>
  <span style="margin-left:auto;color:#888;font-size:0.8rem">Rendered via Plurimath → MathML</span>
</div>
<div class="entries" id="entries"></div>
<script>
__PLURIMATH_BUNDLE__
</script>
<script>
const ENTRIES = __ENTRIES_JSON__;
const GIF_CACHE = __GIF_JSON__;
const STORAGE_KEY = 'cie-math-corrections';
const INITIAL_CORRECTIONS = __INITIAL_CORRECTIONS_JSON__;
let corrections = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
// Merge any corrections embedded at generation time (from --corrections flag)
for (var ck in INITIAL_CORRECTIONS) { corrections[ck] = INITIAL_CORRECTIONS[ck]; }
localStorage.setItem(STORAGE_KEY, JSON.stringify(corrections));

function entryKey(e) { return e.termid + '|' + e.location + '|' + e.gif; }
function escapeHtml(s) { return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }

function renderMath(expr) {
  if (!expr || !expr.trim()) return '<em style="color:#ccc">empty</em>';
  if (!window.PlurimathRenderer) return '<em style="color:#999">loading...</em>';
  var mml = window.PlurimathRenderer.toMathML(expr, 'asciimath');
  if (mml) return mml.replace('display="block"', 'display="inline"');
  return '<code style="color:#c00">' + escapeHtml(expr) + '</code>';
}

let currentFilter = '', currentKind = '', currentStatus = '';

function renderEntries() {
  const container = document.getElementById('entries');
  container.innerHTML = '';
  let shown = 0;
  for (let i = 0; i < ENTRIES.length; i++) {
    const e = ENTRIES[i];
    const key = entryKey(e);
    const isSaved = corrections[key] !== undefined;
    const expr = corrections[key] ?? e.current ?? '';
    if (currentFilter && !e.termid.includes(currentFilter)) continue;
    if (currentKind && e.kind !== currentKind) continue;
    if (currentStatus === 'saved' && !isSaved) continue;
    if (currentStatus === 'unsaved' && isSaved) continue;
    shown++;
    const gifB64 = GIF_CACHE[e.gif] || '';
    const locClass = e.location === 'designation' ? 'designation' : '';
    const div = document.createElement('div');
    div.className = 'entry ' + e.location.split('-')[0] + (isSaved ? ' corrected' : '');
    div.dataset.key = key;
    div.innerHTML =
      '<div class="entry-header">' +
        '<span class="termid">' + e.termid + '</span>' +
        '<span class="location ' + locClass + '">' + e.location + '</span>' +
        '<span class="kind">' + (e.kind === 'designation-symbol' ? 'designation symbol' : 'equation') + '</span>' +
        '<span class="gif-name">' + e.gif + '</span>' +
      '</div>' +
      '<div class="context">' + escapeHtml(e.context || '') + '</div>' +
      '<div class="entry-body">' +
        '<div><div class="col-title">Original GIF</div>' +
          '<div class="gif-cell">' + (gifB64 ? '<img src="' + gifB64 + '" alt="' + e.gif + '"/>' : '<em>not found</em>') + '</div>' +
        '</div>' +
        '<div><div class="col-title">AsciiMath (stem:[] content)</div>' +
          '<div class="edit-cell"><textarea id="ta-' + i + '" oninput="liveRender(' + i + ', this.value)" placeholder="Type AsciiMath...">' + escapeHtml(expr) + '</textarea></div>' +
        '</div>' +
        '<div><div class="col-title">Rendered (Plurimath MathML)</div>' +
          '<div class="render-cell" id="render-' + i + '">' + renderMath(expr) + '</div>' +
        '</div>' +
      '</div>' +
      '<div class="entry-actions">' +
        '<button class="save" onclick="saveEntry(' + i + ')">Save</button>' +
        '<button class="reset" onclick="resetEntry(' + i + ')">Reset</button>' +
      '</div>' +
      '<div class="status ' + (isSaved ? 'saved' : '') + '" id="status-' + i + '">' + (isSaved ? 'Saved' : '') + '</div>';
    container.appendChild(div);
  }
  document.getElementById('stats').textContent = shown + ' shown | ' + Object.keys(corrections).length + '/' + ENTRIES.length + ' corrected | ' + (ENTRIES.length - Object.keys(corrections).length) + ' remaining';
}

function applyFilter() {
  currentFilter = document.getElementById('filter').value;
  currentKind = document.getElementById('kind-filter').value;
  currentStatus = document.getElementById('status-filter').value;
  renderEntries();
}

function liveRender(idx, value) {
  const cell = document.getElementById('render-' + idx);
  if (!cell) return;
  cell.innerHTML = renderMath(value);
}

function saveEntry(idx) {
  const e = ENTRIES[idx];
  if (!e) return;
  const key = entryKey(e);
  const ta = document.getElementById('ta-' + idx);
  if (!ta) return;
  corrections[key] = ta.value;
  localStorage.setItem(STORAGE_KEY, JSON.stringify(corrections));
  const status = document.getElementById('status-' + idx);
  if (status) { status.textContent = 'Saved'; status.className = 'status saved'; }
  const entry = document.querySelector('[data-key="' + CSS.escape(key) + '"]');
  if (entry) entry.classList.add('corrected');
}

function resetEntry(idx) {
  const e = ENTRIES[idx];
  if (!e) return;
  const key = entryKey(e);
  delete corrections[key];
  localStorage.setItem(STORAGE_KEY, JSON.stringify(corrections));
  renderEntries();
}

function saveAll() {
  for (let i = 0; i < ENTRIES.length; i++) {
    const key = entryKey(ENTRIES[i]);
    const ta = document.getElementById('ta-' + i);
    if (ta && ta.value.trim()) corrections[key] = ta.value;
  }
  localStorage.setItem(STORAGE_KEY, JSON.stringify(corrections));
  renderEntries();
  alert('Saved ' + Object.keys(corrections).length + ' corrections');
}

function exportJSON() {
  var data = Object.entries(corrections).map(function(entry) {
    var parts = entry[0].split('|');
    return { termid: parts[0], location: parts[1], gif: parts[2], expression: entry[1] };
  });
  var blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
  var url = URL.createObjectURL(blob);
  var a = document.createElement('a');
  a.href = url; a.download = 'math-corrections.json'; a.click();
  URL.revokeObjectURL(url);
}

function importJSON(input) {
  var file = input.files[0];
  if (!file) return;
  var reader = new FileReader();
  reader.onload = function(e) {
    try {
      var data = JSON.parse(e.target.result);
      var merged = 0;
      for (var i = 0; i < data.length; i++) {
        var entry = data[i];
        var key = entry.termid + '|' + entry.location + '|' + entry.gif;
        corrections[key] = entry.expression;
        merged++;
      }
      localStorage.setItem(STORAGE_KEY, JSON.stringify(corrections));
      renderEntries();
      alert('Imported ' + merged + ' corrections. Total: ' + Object.keys(corrections).length);
    } catch(err) {
      alert('Error reading JSON: ' + err.message);
    }
  };
  reader.readAsText(file);
  input.value = '';
}

window.addEventListener('plurimath-ready', function() {
  document.getElementById('loading-overlay').classList.add('hidden');
  renderEntries();
});

// Fallback: if plurimath-ready already fired before listener attached
if (window.PlurimathRenderer && window.PlurimathRenderer.ready) {
  document.getElementById('loading-overlay').classList.add('hidden');
  renderEntries();
}
</script>
</body>
</html>
"""


def extract_gif_locations():
    entries = []
    for html_path in sorted(glob.glob(PAGES_DIR + "/*.html")):
        termid = os.path.basename(html_path).replace(".html", "")
        html = open(html_path).read()
        para_re = re.compile(r'<p\s+class="(TermEntry|Definition|Note)"[^>]*>(.*?)</p>', re.DOTALL)
        note_counter = 0
        for pm in para_re.finditer(html):
            cls, body = pm.group(1), pm.group(2)
            if cls == "Note":
                if '<span class="NoteLabel">' not in body:
                    continue
                location = "note-" + str(note_counter)
                note_counter += 1
            elif cls == "Definition":
                location = "definition"
            elif cls == "TermEntry":
                location = "designation"
            else:
                continue
            for gm in re.finditer(r'<img\s+class="math"\s+src="http://cie\.co\.at/importfiles/(mml_\w+\.gif)"', body):
                context = re.sub(r'<[^>]+>', '', body).strip()[:200]
                entries.append({
                    "termid": termid, "location": location,
                    "gif": gm.group(1), "context": context,
                    "kind": "designation-symbol" if location == "designation" else "equation",
                })
    return entries


def load_current_expressions(entries):
    by_term = {}
    for e in entries:
        by_term.setdefault(e["termid"], []).append(e)

    for termid, term_entries in by_term.items():
        yaml_path = CONCEPTS_DIR + "/" + termid + ".yaml"
        if not os.path.exists(yaml_path):
            for e in term_entries:
                e["current"] = ""
            continue

        docs = list(yaml.safe_load_all(open(yaml_path)))
        designation_symbols = []
        def_stems = []
        note_stems = []

        for doc in docs:
            if not doc:
                continue
            data = doc.get("data", {})
            for t in data.get("terms", []):
                if t.get("type") == "symbol":
                    designation_symbols.append(t.get("designation", ""))
            for d in data.get("definition", []):
                c = d.get("content", "") if isinstance(d, dict) else ""
                def_stems.append(re.findall(r'stem:\[([^\]]+)\]', c))
            for n in data.get("notes", []):
                c = n.get("content", "") if isinstance(n, dict) else ""
                note_stems.append(re.findall(r'stem:\[([^\]]+)\]', c))

        for e in term_entries:
            loc = e["location"]
            if loc == "designation":
                e["current"] = designation_symbols[0] if designation_symbols else ""
            elif loc == "definition":
                stems = def_stems[0] if def_stems else []
                idx = sum(1 for x in term_entries if x["location"] == "definition" and id(x) != id(e))
                e["current"] = stems[idx] if idx < len(stems) else ""
            elif loc.startswith("note-"):
                ni = int(loc.split("-")[1])
                stems = note_stems[ni] if ni < len(note_stems) else []
                idx = sum(1 for x in term_entries if x["location"] == loc and id(x) != id(e))
                e["current"] = stems[idx] if idx < len(stems) else ""


def embed_gifs(entries):
    cache = {}
    for e in entries:
        if e["gif"] not in cache:
            path = os.path.join(GIF_DIR, e["gif"])
            if os.path.exists(path):
                data = base64.b64encode(open(path, "rb").read()).decode()
                cache[e["gif"]] = "data:image/gif;base64," + data
            else:
                cache[e["gif"]] = ""
    return cache


def load_corrections(path):
    """Load corrections JSON and convert to {key: expression} dict."""
    if not path or not os.path.exists(path):
        return {}
    data = json.load(open(path))
    result = {}
    for entry in data:
        key = entry["termid"] + "|" + entry["location"] + "|" + entry["gif"]
        result[key] = entry["expression"]
    return result


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Generate math correction editor")
    parser.add_argument("--corrections", "-c", help="Path to math-corrections.json to embed")
    args = parser.parse_args()

    print("Extracting GIF locations...")
    entries = extract_gif_locations()
    print("  " + str(len(entries)) + " entries")

    print("Loading current expressions from YAML...")
    load_current_expressions(entries)

    print("Embedding GIFs as base64...")
    gif_cache = embed_gifs(entries)

    initial_corrections = load_corrections(args.corrections)
    if initial_corrections:
        print("Embedding " + str(len(initial_corrections)) + " corrections from " + args.corrections)

    print("Generating HTML editor...")
    plurimath_js = open(PLURIMATH_BUNDLE).read()
    html = HTML_TEMPLATE
    html = html.replace("__PLURIMATH_BUNDLE__", plurimath_js)
    html = html.replace("__ENTRIES_JSON__", json.dumps(entries, ensure_ascii=False))
    html = html.replace("__GIF_JSON__", json.dumps(gif_cache))
    html = html.replace("__INITIAL_CORRECTIONS_JSON__", json.dumps(initial_corrections, ensure_ascii=False))

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    open(OUT_PATH, "w").write(html)

    desig = sum(1 for e in entries if e["kind"] == "designation-symbol")
    eq = sum(1 for e in entries if e["kind"] == "equation")
    concepts = len(set(e["termid"] for e in entries))
    print("Written to " + OUT_PATH)
    print("  " + str(len(entries)) + " entries, " + str(concepts) + " concepts")
    print("  Designation symbols: " + str(desig) + ", Equations: " + str(eq))
    if initial_corrections:
        print("  Corrections embedded: " + str(len(initial_corrections)) + "/" + str(len(entries)))
    print("  HTML size: " + str(len(html) // 1024) + " KB")


if __name__ == "__main__":
    main()
