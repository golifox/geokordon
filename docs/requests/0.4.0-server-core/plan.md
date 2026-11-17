# План 0.4.0

Работа в отдельном worktree от `main`, ветка `feat/server-core`. Каждый шаг — коммит, после каждого `mise run lint test`.

1. Инструменты: `shfmt`, `bats` в `mise.toml`; задачи `lint`, `fmt`, `test`, `build`; `scripts/build` с `unit_text` и проверкой размера.
2. Ядро: перенос `remote/` в `lib/` и `units/`, единая точка входа, `update` вместо `geokordon-update`, `warp up|down|disable` вместо `geokordon-warp`, установка себя в `/usr/local/sbin`, `flock`, новые пути состояния и миграция.
3. Порты: ручной файл плюс пересчёт найденных из `docker inspect` и ssh; тесты на разбор.
4. Прямой список на сервере: `allow add|del|list|push`; удаление локального `allow.list`.
5. `status`, `--help`, `--version`, справка без аргументов; возврат `rp_filter` при `warp off`.
6. Фронт: `-H`, `-p`, `GEOKORDON_HOST`, вопрос запасным вариантом, одно соединение с вложенным ядром; удаление askpass.
7. bats на всё перечисленное в спецификации; прогон в `debian:12`.
8. `install.sh`, workflow `ci.yml` (lint, test, smoke) и `release.yml`.
9. README, CHANGELOG `[Unreleased]`.
10. Независимое ревью диффа, исправления.
11. Слияние в `main` после зелёного CI; тег `v0.4.0` (релиз собирает workflow).
12. Обновление `167.104.108.53` с перезагрузкой — команды даю владельцу, как в 0.3.1.
