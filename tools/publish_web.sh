#!/usr/bin/env bash
# Exporte le jeu en Web (release) et le publie sur la branche gh-pages.
# Usage : tools/publish_web.sh   (GODOT=/chemin/vers/Godot pour forcer le binaire)
#
# Anti-cache infaillible : GitHub Pages fait garder chaque fichier 10 min par le
# navigateur (y compris index.html). Chaque version est donc publiée dans un dossier
# unique v/<empreinte>/ (adresse jamais vue = jamais en cache). La page d'accueil
# lit latest.txt sans cache puis redirige vers la dernière version.
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-$(ps -axo command= | grep -o '^/.*Godot\.app/Contents/MacOS/Godot' | head -1 || true)}"
[ -x "$GODOT" ] || { echo "Godot introuvable : ouvre l'éditeur ou définis GODOT=..."; exit 1; }

rm -rf build/web && mkdir -p build/web
"$GODOT" --headless --path . --export-release "Web" build/web/index.html 2>&1 | grep -E "ERROR|error" || true
[ -f build/web/index.wasm ] || { echo "Export échoué"; exit 1; }

H="$(cat build/web/index.pck build/web/index.html | md5 -q | cut -c1-10)"
TMP="$(mktemp -d)"
mkdir -p "$TMP/v/$H"
cp build/web/* "$TMP/v/$H/"
echo "$H" > "$TMP/latest.txt"
touch "$TMP/.nojekyll"
cat > "$TMP/index.html" <<'HTML'
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
<title>Le Musée</title>
<style>body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;background:#111;color:#eee;font:18px system-ui,sans-serif}</style>
</head>
<body>
<p id="m">Chargement de la dernière version…</p>
<script>
// Demande la dernière version sans cache, puis redirige vers son adresse unique.
fetch("latest.txt?t=" + Date.now(), { cache: "no-store" })
  .then(r => r.text())
  .then(v => location.replace("v/" + v.trim() + "/index.html"))
  .catch(() => { document.getElementById("m").textContent = "Impossible de charger le jeu, recharge la page."; });
</script>
</body>
</html>
HTML

cd "$TMP"
git init -q -b gh-pages
git config user.name "$(git -C "$OLDPWD" config user.name)"
git config user.email "$(git -C "$OLDPWD" config user.email)"
git config http.postBuffer 157286400
git add -A && git commit -q -m "Export Web du jeu, version $H ($(date '+%Y-%m-%d %H:%M'))"
git push -q -f "$(git -C "$OLDPWD" remote get-url origin)" gh-pages
cd - >/dev/null
rm -rf "$TMP"
echo "VERSION=$H"
echo "Publié : https://asbldream-lab.github.io/test/  (lien direct : https://asbldream-lab.github.io/test/v/$H/)"
