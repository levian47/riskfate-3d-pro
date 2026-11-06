# Документація Riskfate 3D Pro

Це робочий індекс перенесених документів. **Увага:** розділ `source-riskfate-2d/` — незмінений історичний знімок Markdown-документації оригінального 2D-проєкту Riskfate, **не чинний стандарт для 3D-проєкту**.

- Джерело: https://github.com/levian47/riskfate
- Гілка джерела: `main`
- Зафіксований коміт джерела: [`0e730a5`](https://github.com/levian47/riskfate/commit/0e730a5fcf3253953a47285ff47507448d61d245)
- Мета: зберегти правила, концепцію та історію для подальшого контрольованого редагування під Riskfate 3D Pro.

## Основні матеріали

- [Концепція гри](source-riskfate-2d/GAME_CONCEPT.md) — механіки, погоджені принципи та відкриті питання.
- [Основа планування](source-riskfate-2d/PLANNING_FOUNDATION.md) — архітектурні принципи й попередні рішення.
- [Графічні стандарти 2D](source-riskfate-2d/GRAPHICS_GUIDELINES.md) — **не застосовувати автоматично до 3D**.
- [План робіт 2D](source-riskfate-2d/ROADMAP.md) — історичні статуси **не є статусами 3D**.
- [README оригінального проєкту](source-riskfate-2d/README.md) — стан 2D-прототипу.
- [Вихідні інструкції Codex](source-riskfate-2d/AGENTS.source.md) — архів; назву змінено, щоб випадково не активувати правила іншого репозиторію.

## Додаткові звіти

- [Герой: технічний звіт](source-riskfate-2d/assets_source/character_sprites/base_hero_v1/technical_report.md)
- [Графіка 004: README](source-riskfate-2d/assets_source/environment_tests/rf_graphics_004/README.md)
- [Графіка 004: історичний звіт](source-riskfate-2d/assets_source/environment_tests/rf_graphics_004/historical_report.md)
- [Графіка 007: технічний звіт](source-riskfate-2d/assets_source/environment_tests/rf_graphics_007/technical_report.md)
- [Графіка 009: технічний звіт](source-riskfate-2d/assets_source/environment_tests/rf_graphics_009/technical_report.md)

## Адаптація під 3D (поки не виконано)

1. **Механіки гри:** перенести універсальні принципи (прогрес, навички, смерть тощо), перевіряючи статус кожного рішення.
2. **Технічний фундамент:** створити окремі правила 3D-сцен, системи координат, одиниць масштабу, колізій, камери, вводу і Web-експорту.
3. **Графіка:** замінити вимоги до pixel art/спрайтів на стандарти low-poly, матеріалів, моделей та продуктивності.
4. **ROADMAP:** почати від фактичного стану репозиторію 3D, не зараховувати завершені 2D-етапи.
5. **AGENTS:** підготувати окремі чинні інструкції Codex для `levian47/riskfate-3d-pro`, а не копіювати 2D-інструкції в корінь.

Скопійовано лише текстові Markdown-документи. PNG, вихідні графічні ресурси, код, конфігурації та JSON-метадані не перенесені. Тому посилання у вихідних документах на ці ресурси можуть не відкриватися; їх можна переглянути в оригінальному репозиторії на зафіксованому коміті.
