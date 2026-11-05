#!/usr/bin/env bash
# Сборка тестовых версий (пресеты «… (TEST)» из export_presets.cfg; в них признак `playtest`: панель FPS, лог событий, страница «Для тестов»).
#   tools/build_test.sh android|web|windows|linux|all     (по умолчанию all)
# Нужны Godot 4.7 с установленными шаблонами экспорта (Editor → Manage Export Templates) и для Android — JDK 17, Android SDK и debug-keystore
# в Editor Settings → Export → Android. Переменная GODOT задаёт путь к бинарнику (по умолчанию `godot`).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
mkdir -p build/test/web build/test/windows build/test/linux
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
build() {   # имя пресета, файл результата
  echo "== $1"
  "$GODOT" --headless --path . --export-debug "$1" "$2"
  ls -lh "$2"
}
what="${1:-all}"
[[ "$what" == android || "$what" == all ]] && build "Android (TEST — debug APK, arm64)" build/test/warm-paw-test.apk
[[ "$what" == web     || "$what" == all ]] && build "Web (TEST)" build/test/web/index.html
[[ "$what" == windows || "$what" == all ]] && build "Windows (TEST)" build/test/windows/warm-paw-test.exe
[[ "$what" == linux   || "$what" == all ]] && build "Linux (TEST)" build/test/linux/warm-paw-test.x86_64
echo "Готово. Android: adb install -r build/test/warm-paw-test.apk (пакет ru.warmpaw.cafe.test ставится рядом с обычным)."
