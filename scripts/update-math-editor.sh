#!/usr/bin/env bash
# Regenerate the math editor with the latest corrections embedded,
# then zip it for GitHub.
#
# Usage:
#   ./scripts/update-math-editor.sh [corrections.json]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

CORRECTIONS="${1:-reference-docs/reports/math-corrections.json}"

if [ ! -f "$CORRECTIONS" ]; then
  echo "Corrections file not found: $CORRECTIONS"
  exit 1
fi

COUNT=$(python3 -c "import json; print(len(json.load(open('$CORRECTIONS'))))")
echo "Embedding $COUNT corrections from $CORRECTIONS..."

python3 scripts/generate_math_editor.py --corrections "$CORRECTIONS"

# Copy deliverables to docs/math-correction/ (not gitignored)
mkdir -p docs/math-correction
cp "$CORRECTIONS" docs/math-correction/math-corrections.json
zip -9 -j docs/math-correction/math-editor.zip reference-docs/reports/math-editor.html
cp reference-docs/reports/MATH-CORRECTION-WORKFLOW.md docs/math-correction/README.md

ZIP_SIZE=$(du -h docs/math-correction/math-editor.zip | cut -f1)
echo ""
echo "Done. Files in docs/math-correction/:"
echo "  math-editor.zip          ($ZIP_SIZE, self-contained editor)"
echo "  math-corrections.json    ($COUNT corrections)"
echo "  README.md                (workflow + GitHub Issue template)"
echo ""
echo "Commit and push:"
echo "  git add docs/math-correction/"
echo "  git commit -m 'chore: update math editor ($COUNT/242 corrections)'"
