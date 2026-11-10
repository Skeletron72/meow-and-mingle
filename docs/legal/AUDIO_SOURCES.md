# Источники звука

Все звуки и музыка игры — настоящие записи с лицензией **CC0** (общественное достояние), взяты с OpenGameArt. Исходные файлы лежат без изменений
в `assets/audio_src/`, игровые файлы `assets/audio/*.ogg` собирает `python3 tools/build_audio.py` (вырезка фрагмента, плавные края, громкость;
сдвиг высоты и срез верхов — только где указано в таблице скрипта). Указывать авторов CC0 не требует, но они перечислены в титрах игры.

| Звук в игре | Где звучит | Длина, с | Исходный файл | Набор | Автор | Страница |
|---|---|---|---|---|---|---|
| `click` | кнопки интерфейса | 0.04 | `select_002.ogg` | Interface Sounds | Kenney (kenney.nl) | https://opengameart.org/content/interface-sounds |
| `back` | кнопка «Назад» | 0.08 | `back_004.ogg` | Interface Sounds | Kenney (kenney.nl) | https://opengameart.org/content/interface-sounds |
| `tap` | касание в обучении | 0.07 | `back_002.ogg` | Interface Sounds | Kenney (kenney.nl) | https://opengameart.org/content/interface-sounds |
| `pick` | автосборка заказа | 0.10 | `drop_003.ogg` | Interface Sounds | Kenney (kenney.nl) | https://opengameart.org/content/interface-sounds |
| `pop` | выпечка или добавка легла на поднос (чашка о стол) | 0.38 | `cup_on_table_01.ogg` | cutlery sounds | TinyWorlds | https://opengameart.org/content/cutlery-sounds |
| `pour` | напиток льётся в чашку | 0.85 | `loop_water_01.ogg` | 40 CC0 water / splash / slime SFX | rubberduck | https://opengameart.org/content/40-cc0-water-splash-slime-sfx |
| `steam` | пар кофемашины, когда наливают кофе | 0.86 | `steam_hiss_1.wav` | Steam release sounds | bart | https://opengameart.org/content/steam-release-sounds |
| `success` | заказ подан (звон тарелки) | 0.24 | `fork_on_dish_01.ogg` | cutlery sounds | TinyWorlds | https://opengameart.org/content/cutlery-sounds |
| `purr` | довольный гость: быстрая подача | 1.38 | `cat_mewpurr.wav` | Cat Purr & Meow | Kerzoven | https://opengameart.org/content/cat-purr-meow |
| `fail` | не тот заказ (глухой стук) | 0.24 | `bookClose.ogg` | 50 RPG sound effects | Kenney (kenney.nl) | https://opengameart.org/content/50-rpg-sound-effects |
| `angry` | гость ушёл недовольным | 1.34 | `cat_mewfood.wav` | Cat Purr & Meow | Kerzoven | https://opengameart.org/content/cat-purr-meow |
| `meow1` | мяу | 0.49 | `Meow.ogg` | Meow | dino1489 | https://opengameart.org/content/meow |
| `meow2` | мяу котёнка | 0.86 | `kitten_mew-1.wav` | Kitten Mew | см. страницу | https://opengameart.org/content/kitten-mew |
| `coin` | монеты в итогах и наградах | 0.30 | `handleCoins2.ogg` | 50 RPG sound effects | Kenney (kenney.nl) | https://opengameart.org/content/50-rpg-sound-effects |
| `star` | звезда, награда | 0.62 | `pleasing-bell.wav` | Pleasing Bell Sound Effect | Spring Spring | https://opengameart.org/content/pleasing-bell-sound-effect |
| `bell` | колокольчик над дверью кафе | 1.16 | `bell_ding2.wav` | Bell dings/chimes | PWL | https://opengameart.org/content/bell-dingschimes |
| `shutter` | ставни кафе | 0.88 | `metal_swing1.wav` | Metal Interactions | qubodup | https://opengameart.org/content/metal-interactions |
| `box` | коробка во вступлении | 0.30 | `dropLeather.ogg` | 50 RPG sound effects | Kenney (kenney.nl) | https://opengameart.org/content/50-rpg-sound-effects |
| `whoosh` | поднос уезжает к гостю | 0.13 | `swish-7.wav` | Swishes Sound Pack | artisticdude | https://opengameart.org/content/swishes-sound-pack |
| `page` | шпаргалка рецептов: открыть, перелистнуть | 0.40 | `bookFlip2.ogg` | 50 RPG sound effects | Kenney (kenney.nl) | https://opengameart.org/content/50-rpg-sound-effects |
| `jingle_win` | итог смены: есть звёзды | 5.39 | `cozy_puzzle_clear_jingle.ogg` | Cozy Puzzle (Title, In-Game 1, Jingle & Result) | MintoDog | https://opengameart.org/content/cozy-puzzle-title |
| `jingle_lose` | итог смены: без звёзд | 5.39 | `cozy_puzzle_failure_jingle.ogg` | Cozy Puzzle (Title, In-Game 1, Jingle & Result) | MintoDog | https://opengameart.org/content/cozy-puzzle-title |
| `music_city` | музыка города (петля) | 60.63 | `cozy_puzzle_title_bpm95.ogg` | Cozy Puzzle (Title, In-Game 1, Jingle & Result) | MintoDog | https://opengameart.org/content/cozy-puzzle-title |
| `music_shift` | музыка смены (петля) | 130.17 | `cozy_puzzle_in-game_1_bpm118.ogg` | Cozy Puzzle (Title, In-Game 1, Jingle & Result) | MintoDog | https://opengameart.org/content/cozy-puzzle-title |

Проверено при загрузке (2026-11-10): на странице каждого набора указана лицензия CC0. Сохраните снимки страниц в `docs/legal/receipts/` перед релизом.
