# Сторонние ассеты (распакованные архивы)

Все паки 16×16, оригинальная структура папок сохранена.

| Папка | Что внутри | Источник | Условия |
|---|---|---|---|
| `neko-cafe/` | 3 кота (спереди/сбоку/сзади), мебель, тайлы, выпечка | [Neko Cafe Asset Pack](https://hellorumin.itch.io/neko-cafe-asset-pack) | Коммерция разрешена, можно менять, нельзя перепродавать, автор просит титры |
| `pixel-food-16x16/` | 100 иконок еды и напитков | [100 Free Pixel Art Foods](https://alexkovacsart.itch.io/free-pixel-art-foods) (Alex) | CC BY 4.0, титры обязательны |
| `cozy-ui-demo/` | Кнопки, рамки, контейнеры, иконки, модалки | [Mega Cozy UI Pack, DEMO](https://dobo-ui.itch.io/) (dobo_ui) | **Не проверено**: лицензию DEMO сверить вручную до релиза |
| `topdown-vehicles/` | Транспорт сверху, анимации (30 тыс. файлов) | [TopDown Vehicles v1.17](https://minzinn.itch.io/) (MinZiin_) | CC BY 4.0, титры обязательны |
| `city-essentials/` | 50+ городских объектов | Ranitaya's 50+ City Essential Assets Pack | **Не проверено**: лицензию сверить на странице пака |

PostApocalypse Asset Pack (TheLazyStone) в репозиторий не добавлен: его лицензия запрещает распространение, а репозиторий публичный.

`assets/packs` закрыта от импорта Godot (`.gdignore`): здесь исходники паков (около 30 тысяч файлов). В игре используются копии в
`assets/street` (здания, объекты, машины — делает `tools/curate_street_assets.py`), `assets/cats`, `assets/cafe`, `assets/ui`.
Если нужен новый спрайт из пака — добавьте его в скрипт отбора и запустите заново.

Нужные авторы для экрана титров: hellorumin, Alex Kovacs (CC BY 4.0), автор Specialty Coffee, dobo_ui.


**Удалено из репозитория:** `modern-interiors-free` (только некоммерческое использование — в релиз не годится), `cosy-cabin`, `pixel-16-interiors`
(не используются, лицензия не проверена). Сводка по лицензиям и проверка файлов — `docs/legal/ASSET_LICENSES.md`, `python3 tools/audit_assets.py`.
