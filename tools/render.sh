#!/usr/bin/env bash
# Render tools/screens.lua output to PNG contact sheets (needs Chromium)
set -euo pipefail
OUT="${1:-shots}"
mkdir -p "$OUT"
lua tools/screens.lua "$OUT"
CHROME="${CHROME:-$(ls /opt/pw-browsers/chromium-*/chrome-linux/chrome 2>/dev/null | head -1)}"
cd "$OUT"
i=0
for f in *.svg; do
  i=$((i+1))
  echo "<html><body style='margin:0;overflow:hidden'><img src='$f' width='636' height='424'></body></html>" > "${f%.svg}.html"
  "$CHROME" --headless --no-sandbox --disable-gpu --hide-scrollbars --screenshot="$PWD/${f%.svg}.png" --window-size=636,520 "file://$PWD/${f%.svg}.html" >/dev/null 2>&1
done
echo "rendered $i screens to $OUT"
