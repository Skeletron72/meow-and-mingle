#!/bin/bash
# Запуск всех автотестов под виртуальным дисплеем (нужны godot 4.4+, xvfb, mesa).
# Использование: tests/run_all.sh
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
RUN="xvfb-run -a -s '-screen 0 1280x720x24' $GODOT --path . --rendering-driver opengl3"
fail=0

echo "== play_test (игровой цикл)"
out=$(eval timeout 300 $RUN res://tests/play_test.tscn 2>&1)
echo "$out" | grep -E "OK|FAIL|Итого"
echo "$out" | grep -q "ВСЁ ХОРОШО" || fail=1

echo "== walk_test (движение, жители)"
out=$(eval timeout 120 $RUN res://tests/walk_test.tscn 2>&1)
echo "$out" | grep -E "игрок|реки|гуляют"
echo "$out" | grep -qE "гуляют: [1-9]" || fail=1

echo "== finale_test (финал сюжета)"
out=$(eval timeout 120 $RUN res://tests/finale_test.tscn 2>&1)
echo "$out" | grep -E "финал"
echo "$out" | grep -q "ключ=1 флаг=true" || fail=1

echo "== smoke (меню → вступление → прибытие)"
out=$(QH_AUTO=1 eval timeout 120 $RUN res://scenes/intro.tscn 2>&1)
echo "$out" | grep -E "smoke"
echo "$out" | grep -q "игрок управляет: true" || fail=1

if echo "$out" | grep -q "SCRIPT ERROR"; then echo "Есть SCRIPT ERROR!"; fail=1; fi
[ $fail -eq 0 ] && echo "ВСЕ ТЕСТЫ ПРОШЛИ" || echo "ЕСТЬ ПРОВАЛЫ"
exit $fail
