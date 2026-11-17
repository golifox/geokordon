# 0.4.0: ядро на сервере, один файл, флаги цели, CI

Статус: черновик на согласование. Основа — `tmp/review-findings.md` (находки 4–6 и мелочи), решения владельца от 2026-11-17:

- ставить ядро обоими путями: фронтом с ноутбука и `curl … | sudo bash` из релиза;
- локальный `allow.list` убрать, источник истины — сервер;
- `install` переносит состояние 0.3.x в новые пути;
- CI: lint, bats, дымовой тест на раннерах Ubuntu.

## Цель

Один файл `geokordon` служит и ядром на сервере, и фронтом на ноутбуке. Вся логика выполняется на сервере и остаётся там после установки: `sudo geokordon warp on` работает без ноутбука. Фронт только доставляет файл своей версии по ssh и вызывает его; цель задаётся флагом, вопросы — запасной вариант.

## Интерфейс

```
geokordon [-H TARGET] [-p PORT] COMMAND
  install [--with-warp | --without-warp]
  update                 скачать списки, пересобрать и применить правила
  status                 версия, таймер, последнее обновление, префиксы, порты, прямой список, WARP
  warp on | warp off
  allow add ENTRY... | allow del ENTRY... | allow list | allow push FILE
  remove
  --help (код 0), --version
```

- Без аргументов: справка в stderr, код 2.
- `-H TARGET` или `GEOKORDON_HOST`: строка уходит в `ssh` как есть, поэтому работают `user@host`, алиасы и всё из `~/.ssh/config`. `-p PORT` уходит в `ssh -p`.
- Без цели на Linux команда выполняется локально (нужен root; иначе подсказка про `sudo` и `-H`). Без цели не на Linux: при терминале один вопрос «Server (user@host or ssh alias):», без терминала — ошибка.
- `warp up|down|disable` — служебные подкоманды для `geokordon-warp.service` и таймера отката, в справке не показываются.

## Доставка с ноутбука

Одно ssh-соединение, поэтому пароль ssh и пароль sudo спрашиваются по одному разу, а временный файл не остаётся на сервере при обрыве второго соединения:

```
ssh [-p PORT] [-t] TARGET '<sh-скрипт>'
```

Скрипт: создаёт `mktemp -d` с `trap` на удаление, распаковывает в него ядро из `base64 | gunzip`, вложенного в команду (для `allow push` — ещё и список), и запускает `bash "$d/geokordon" ARGS`, через `sudo`, если `id -u` не 0. Аргументы экранируются для POSIX sh одинарными кавычками; `$*` больше нет.

- `-t`, только когда у фронта есть терминал: тогда sudo сам спрашивает пароль. Без терминала — `sudo -n`, при отказе подсказка про NOPASSWD.
- `SSH_ASKPASS`, ввод пароля в фронте и требование OpenSSH 8.4+ уходят.
- Сборка падает, если сжатое ядро в base64 больше 96 KB (одна строка аргумента на Linux ограничена 128 KB).
- Фронт, запущенный из исходников, собирает файл на лету тем же скриптом сборки.

## Ядро на сервере

- `install` кладёт себя в `/usr/local/sbin/geokordon`. Любая другая команда, кроме `remove`, запущенная не из установленного пути, обновляет установленную копию, если та отличается: юниты всегда вызывают ту же версию, что и фронт.
- Юниты встроены в файл: `geokordon.service` (`geokordon update`), `geokordon.timer`, `geokordon-restore.service` (без изменений по сути), `geokordon-warp.service` (`geokordon warp up|down`).
- Изменяющие команды берут `flock /run/geokordon.lock`; таймер и ручной запуск больше не сталкиваются.
- Состояние:

| Путь | Что |
| --- | --- |
| `/etc/geokordon/allow` | прямой список, правится `allow add|del|push` |
| `/etc/geokordon/ports` | порты, открытые вручную (`tcp 2222`); сюда же переносится старый `/etc/geokordon.ports` |
| `/etc/geokordon/warp/` | аккаунт wgcf, исходное значение `rp_filter` |
| `/var/lib/geokordon/` | кэш списков, найденные порты, `allow.resolved`, `geokordon.nft` |

### Порты

Найденные порты пересчитываются при каждом `update`, а не копятся: порты sshd (`sshd -T`, слушатели `sshd`, `ssh.socket`) и порты контейнеров `amnezia*` из `docker inspect .HostConfig.PortBindings`. Этот источник видит и остановленные контейнеры, и диапазоны (Docker разворачивает их поштучно; проверено). Удалённый контейнер закрывает свои порты при следующем обновлении. Ручные порты из `/etc/geokordon/ports` добавляются всегда.

### Прямой список

`allow add|del|list|push` работают с `/etc/geokordon/allow` и сразу применяют `update`; проверка записей одна (в файле одна функция, без копии на фронте). `install` список не трогает. `allow push FILE` заменяет список целиком и показывает разницу со старым.

### WARP

Логика `remote/warp.sh` и `geokordon-warp` объединяется. `warp on` сохраняет исходный `rp_filter` в `/etc/geokordon/warp/`, `warp off` и `remove` его возвращают.

### Миграция с 0.3.x (в `install`)

Если новых файлов ещё нет: `/etc/geokordon.allow` → `/etc/geokordon/allow`, `/etc/geokordon.ports` → `/etc/geokordon/ports`, `/etc/geokordon-warp` → `/etc/geokordon/warp`. Удаляются `/usr/local/sbin/geokordon-update` и `geokordon-warp`. Юниты перезаписываются; если WARP был включён, `geokordon-warp.service` перезапускается на новом `ExecStart`.

## Исходники и сборка

```
geokordon             точка входа: разбор аргументов, фронт или ядро
lib/*.sh              модули: common, front, install, update, warp, allow, status, remove
units/                юниты systemd
install.sh            установщик для curl | bash
scripts/build         склеивает geokordon, lib и units в dist/geokordon
test/*.bats           тесты
```

Сборка подставляет модули вместо `source` и превращает юниты в функцию `unit_text NAME`. Версия — константа `GEOKORDON_VERSION` в `geokordon`; релиз проверяет, что она совпадает с тегом. `remote/` и `allow.list.example` удаляются. Запуск из исходников (`./geokordon …`) работает как раньше.

mise: `shellcheck`, `shfmt`, `bats`; задачи `lint`, `fmt`, `test`, `build`.

## Установка на сервере

```
curl -fsSL https://github.com/golifox/geokordon/releases/latest/download/install.sh | sudo bash -s -- --with-warp
```

`install.sh` скачивает `geokordon` и `SHA256SUMS` из того же релиза (`GEOKORDON_VERSION=v0.4.0` закрепляет версию), сверяет сумму, кладёт файл в `/usr/local/sbin` и вызывает `geokordon install "$@"`.

## CI (GitHub Actions)

- `lint`: shellcheck, `shfmt -d`.
- `test`: bats в контейнере `debian:12` с `--cap-add NET_ADMIN`: проверка записей прямого списка, подсчёт и пороги ipdeny, разбор портов из вывода `docker inspect`, генерация правил и `nft -c` на них, экранирование аргументов фронта (круг через `sh -c`), миграция путей.
- `smoke`: `ubuntu-22.04` и `ubuntu-24.04` прямо на раннере: собрать, запустить контейнер `amnezia-ci` с опубликованным UDP-портом, `sudo dist/geokordon install`, `status` (порт найден, набор `ru4` не пуст, `geokordon-restore.service` включён), `allow add`/`del`, `remove` (таблицы и файлов нет). WARP в CI не включается: регистрация у Cloudflare из CI ненадёжна.
- `release` по тегу `v*`: сборка, проверка версии, `SHA256SUMS`, релиз с `geokordon`, `install.sh`, `SHA256SUMS` и разделом CHANGELOG в описании.

## Вне объёма

dnf и другие дистрибутивы, конфиг стран и шаблона контейнеров, README на русском, `SECURITY.md`, `.deb`, Homebrew. Это следующие версии по плану.

## Риски

- Фронт без терминала и пользователь не root без NOPASSWD: команда падает с подсказкой, как и сейчас.
- Порт SSH больше не передаётся фронтом: он берётся из `sshd -T`, слушателей и `ssh.socket`. Если sshd слушает порт, которого нет ни там, ни в `/etc/geokordon/ports`, вход из российских сетей закроется; `install` печатает открытые порты.
- Остановленный контейнер с незаданным `HostPort` (случайный порт) не даёт порта, пока не запущен; у Amnezia порты заданы явно.

## Готово, когда

- CI зелёный на всех задачах; `mise run lint test build` проходит локально.
- `167.104.108.53` обновлён с 0.3.1 фронтом 0.4.0: прямой список, порты и WARP сохранились, `sudo geokordon status` на сервере показывает их, перезагрузка поднимает правила.
- README описывает три способа запуска и новые команды; CHANGELOG — изменения и путь обновления.
