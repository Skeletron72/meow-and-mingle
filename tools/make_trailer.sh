#!/usr/bin/env bash
# Трейлер: сырая запись игры (tools/store_trailer.gd → raw.avi, 1080×1920 = игра ровно ×3) + подписи и финальный кадр в той же сетке пикселей.
#   tools/make_trailer.sh <raw.avi> [ru|en]      → store/<lang>/video/trailer_1080x1920.mp4
# Подписи — готовые картинки (tools/make_trailer_art.py), а не текст ffmpeg: так пиксель шрифта равен пикселю игры и нет сглаживания.
# Тайминги совпадают с метками MARK, которые печатает store_trailer.gd (A 0–3,1 / B –7,1 / C –18,6 / D –23,3 / E –26,3 / F –28,5).
set -euo pipefail
cd "$(dirname "$0")/.."
RAW="$1"; LANG_="${2:-ru}"
OUT="store/${LANG_}/video"; mkdir -p "$OUT"
TMP="$(mktemp -d)"
ffmpeg -v error -y -ss 1.5 -i "$RAW" -frames:v 1 "$TMP/facade.png"
python3 tools/make_trailer_art.py "$TMP" "$LANG_" "$TMP/facade.png"
T=(0 3.1 7.1 12.6 18.6 23.3 26.3); E=(3.1 7.1 12.6 18.6 23.3 26.3 28.5)
IN=(); FC="[0:v]fps=30[v0]"
for i in 0 1 2 3 4 5 6; do
  IN+=(-i "$TMP/c$i.png")
  FC+=";[v$i][$((i + 1)):v]overlay=0:0:enable='between(t,${T[$i]},${E[$i]})'[v$((i + 1))]"
done
ffmpeg -v error -y -i "$RAW" "${IN[@]}" -loop 1 -t 3.6 -framerate 30 -i "$TMP/end.png" -filter_complex \
  "${FC};[8:v]fps=30,format=yuv420p,fade=t=in:st=0:d=0.4[end];[v7]format=yuv420p[m];[m][end]concat=n=2:v=1:a=0[v];[0:a]afade=t=out:st=26.8:d=1.7,apad=pad_dur=3.6[a]" \
  -map "[v]" -map "[a]" -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p -r 30 -c:a aac -b:a 160k -movflags +faststart -shortest "$OUT/trailer_1080x1920.mp4"
ls -lh "$OUT/trailer_1080x1920.mp4"
