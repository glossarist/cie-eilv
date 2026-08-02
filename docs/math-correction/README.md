# Math Correction Workflow

Round-trip workflow for correcting the 242 math equations in the CIE e-ILV
dataset. Each equation was originally a MathML GIF on the CIE website;
this editor lets a human transcribe each GIF into AsciiMath (`stem:[]`)
notation with a live Plurimath MathML preview.

## Files

| File | Purpose |
|---|---|
| `docs/math-correction/math-editor.zip` | Self-contained editor (644 KB zipped, 3.7 MB unzipped). Includes all GIFs (base64), Plurimath engine, and current corrections. |
| `docs/math-correction/math-corrections.json` | Canonical corrections file. Tracked in git. Updated each round. |
| `scripts/generate_math_editor.py` | Regenerates the HTML from cached pages + YAML + corrections. |
| `scripts/update-math-editor.sh` | One-command regenerate + zip + copy deliverables. |

## Round-trip

```
Maintainer                          Editor
──────────                          ──────
1. Run update-math-editor.sh        1. Download math-editor.zip
   with latest corrections             from the GitHub Issue
2. Commit + push                    2. Unzip, open math-editor.html
3. Create/update Issue              3. (Optional) Import JSON
   with download links                to load existing corrections
                                    4. Correct equations
                                    5. Export JSON
                                    6. Attach JSON to Issue
─────────────────────────────────── ───────────────────────────────
7. Download editor's JSON
8. Run update-math-editor.sh
9. Commit + push
10. Comment on Issue:
    "Updated: X/242 done"
                    └─────────────► back to step 1
```

## For the maintainer

### After receiving corrections from the editor:

```bash
# 1. Download the editor's math-corrections.json (from Issue attachment)
#    and place it at reference-docs/reports/math-corrections.json

# 2. Regenerate + zip + copy deliverables
./scripts/update-math-editor.sh

# 3. Commit and push
git add docs/math-correction/
git commit -m "chore: update math editor (NN/242 corrections)"

# 4. Comment on the Issue with the new count
```

### To create the initial Issue:

Use this body template:

---
**Title:** Math equation corrections — 242 equations need AsciiMath transcription

**Body:**

The CIE e-ILV dataset has 242 math equations that were originally rendered
as GIF images on the CIE website. Each needs to be transcribed into
AsciiMath notation.

**Current progress: 25/242 corrected (217 remaining)**

### How to help

1. Download the editor (zip, 644 KB):
   [math-editor.zip](https://github.com/glossarist/cie-eilv/raw/main/docs/math-correction/math-editor.zip)

2. Unzip, then open `math-editor.html` in any browser (Chrome, Firefox, Safari).
   Fully self-contained — no internet needed after download.

3. (Optional) Download the current corrections and click **Import JSON**
   to load them:
   [math-corrections.json](https://github.com/glossarist/cie-eilv/raw/main/docs/math-correction/math-corrections.json)

4. For each entry:
   - Look at the **Original GIF** (left column)
   - Type the AsciiMath expression in the **text box** (middle column)
   - Check the **Plurimath MathML preview** (right column) matches the GIF
   - Click **Save**

5. When done (or partially done), click **Export JSON**.

6. Attach the exported `math-corrections.json` to a comment on this issue.

### AsciiMath cheat sheet

| Symbol | AsciiMath |
|---|---|
| Subscript | `Phi_e`, `x_0` |
| Superscript | `x^2`, `10^-3` |
| Greek | `lambda`, `Phi`, `Delta`, `nu`, `sigma` |
| Fraction | `(d Q_e)/(d t)` or `a/b` |
| Integral | `int_0^oo f(x) dx` |
| Derivative | `(dX)/(dlambda)` |
| Multiplication | `cdot` or `xx` |
| Approximately | `~~` |
| Infinity | `oo` |
| Units | keep outside math: `stem:[E]` in `W⋅sr^(-1)` |

### Tips

- Use the **filter bar** to find specific concepts by termid
- Filter by **type** to see only designation symbols or only equations
- Filter by **status** to see only unsaved entries
- Green left border = already corrected
- Yellow left border = designation symbol (the concept's math symbol)
- Your work is saved to the browser's localStorage — closing the tab
  won't lose it. But always **Export JSON** before sending.

---

## For the editor

### Opening the editor

1. Download and unzip `math-editor.zip` from the Issue link
2. Open `math-editor.html` in Chrome/Firefox/Safari
3. Wait for "Loading Plurimath engine..." to disappear (~2 seconds)

### Loading existing corrections (if any)

If you received a `math-corrections.json` alongside the HTML:
1. Click **Import JSON** in the toolbar
2. Select the file
3. Existing corrections appear with green borders

### Correcting equations

Each row shows:
- **TermID + location** (e.g., `17-21-038 | definition`)
- **Original GIF** — the equation as it appears on cie.co.at
- **AsciiMath text box** — type the expression here
- **Plurimath preview** — live MathML rendering

Type the AsciiMath and check the preview matches the GIF. Click **Save**
when correct.

### Sending corrections back

Click **Export JSON** → attaches `math-corrections.json` → upload to the Issue.
