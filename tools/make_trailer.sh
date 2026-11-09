#!/usr/bin/env bash
# Трейлер: сырая запись игры (tools/store_trailer.gd → raw.avi) + подписи + финальная плашка → store/ru/video/trailer_1080x1920.mp4
#   tools/make_trailer.sh <raw.avi> [ru|en]
# Тайминги подписей совпадают с метками MARK, которые печатает store_trailer.gd (A 0–3,1 / B –7,1 / C –18,6 / D –23,3 / E –26,3 / F –28,5).
set -euo pipefail
cd "$(dirname "$0")/.."
RAW="$1"; LANG_="${2:-ru}"
FONT="assets/fonts/Galmuri11.ttf"
OUT="store/${LANG_}/video"; mkdir -p "$OUT"
TMP="$(mktemp -d)"
python3 tools/make_endcard.py "$TMP/end.png" "$LANG_"
if [[ "$LANG_" == "ru" ]]; then
  C=("Мама оставила кафе…" "…пора его открыть!" "Готовь, добавляй, подавай!" "27 напитков с начинками" "Очки, звёзды и чаевые" "Коты с талантами" "Обставь кафе по-своему")
else
  C=("Mom left her café…" "…time to open it!" "Brew, top up, serve!" "27 drinks with toppings" "Points, stars and tips" "Cats with talents" "Decorate it your way")
fi
T=(0 3.1 7.1 12.6 18.6 23.3 26.3); E=(3.1 7.1 12.6 18.6 23.3 26.3 28.5)
VF="[0:v]fps=30"
for i in 0 1 2 3 4 5 6; do
  printf '%s' "${C[$i]}" > "$TMP/c$i.txt"
  VF+=",drawtext=fontfile=$FONT:textfile=$TMP/c$i.txt:fontsize=60:fontcolor=0xfffaee:box=1:boxcolor=0x3b2a3d@0.88:boxborderw=26:x=(w-text_w)/2:y=330:enable='between(t,${T[$i]},${E[$i]})'"
done
VF+="[main]"
ffmpeg -v error -y -i "$RAW" -loop 1 -t 3.6 -framerate 30 -i "$TMP/end.png" -filter_complex \
  "${VF};[1:v]fps=30,format=yuv420p,fade=t=in:st=0:d=0.5[end];[main]format=yuv420p[m];[m][end]concat=n=2:v=1:a=0[v];[0:a]afade=t=out:st=26.8:d=1.7,apad=pad_dur=3.6[a]" \
  -map "[v]" -map "[a]" -c:v libx264 -crf 20 -preset slow -pix_fmt yuv420p -r 30 -c:a aac -b:a 160k -movflags +faststart -shortest "$OUT/trailer_1080x1920.mp4"
ls -lh "$OUT/trailer_1080x1920.mp4"
