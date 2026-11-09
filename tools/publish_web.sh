#!/usr/bin/env bash
# Exporte le jeu en Web (release) et le publie sur la branche gh-pages.
# Usage : tools/publish_web.sh   (GODOT=/chemin/vers/Godot pour forcer le binaire)
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-$(ps -axo command= | grep -o '^/.*Godot\.app/Contents/MacOS/Godot' | head -1 || true)}"
[ -x "$GODOT" ] || { echo "Godot introuvable : ouvre l'éditeur ou définis GODOT=..."; exit 1; }

rm -rf build/web && mkdir -p build/web
"$GODOT" --headless --path . --export-release "Web" build/web/index.html 2>&1 | grep -E "ERROR|error" || true
[ -f build/web/index.wasm ] || { echo "Export échoué"; exit 1; }

TMP="$(mktemp -d)"
cp build/web/* "$TMP/" && touch "$TMP/.nojekyll"
cd "$TMP"
git init -q -b gh-pages
git config user.name "$(git -C "$OLDPWD" config user.name)"
git config user.email "$(git -C "$OLDPWD" config user.email)"
git config http.postBuffer 157286400
git add -A && git commit -q -m "Export Web du jeu ($(date '+%Y-%m-%d %H:%M'))"
git push -q -f "$(git -C "$OLDPWD" remote get-url origin)" gh-pages
rm -rf "$TMP"
echo "Publié : https://asbldream-lab.github.io/test/"
