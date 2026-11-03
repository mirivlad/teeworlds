# Teeworlds с ботами — Docker / Portainer

Это форк [официального Teeworlds](https://github.com/teeworlds/teeworlds), в который перенесены боты из [nheir/teeworlds (server_bot0.7)](https://github.com/nheir/teeworlds/tree/server_bot0.7). Основа — актуальная upstream-ветка `master` на дату интеграции, а не устаревшая копия 0.7.5. Движок и сетевые исправления остаются из официального проекта. Клиент 0.7.x изменять не нужно.

## Portainer

Откройте **Stacks → Add stack → Web editor** и вставьте [compose.yaml](compose.yaml). Укажите порт UDP 8303 на хосте и нажмите Deploy.

Образ: `ghcr.io/mirivlad/teeworlds-bots:latest`.

Он публикуется GitHub Actions в GHCR после обновления ветки `master`. Первая публикация должна завершиться успешно до установки стека.

Официальные карты **уже входят в образ**, дополнительные загрузки не нужны: они поставляются как Git-подмодуль `datasrc/maps` от `teeworlds/teeworlds-maps`, а сборка переносит их в каталог `data/maps` контейнера. Для публикации используется `actions/checkout` с `submodules: recursive`.

### Настройки

Меняйте переменные `environment` в compose-файле и обновляйте стек:

| Переменная | По умолчанию | Назначение |
|---|---:|---|
| `TW_SERVER_NAME` | Teeworlds Bots | Имя сервера |
| `TW_MAP` | dm1 | Официальная карта |
| `TW_GAME_TYPE` | dm | dm / tdm / ctf |
| `TW_MAX_CLIENTS` | 16 | Всего мест на сервере |
| `TW_PLAYER_SLOTS` | 12 | Игровые слоты |
| `TW_BOT_SLOTS` | 4 | Число ботов (освобождают место для людей) |
| `TW_BOT_ALWAYS_ENABLE` | 2 | 0 — только с игроками; 1 — существуют без игроков; 2 — играют без игроков |
| `TW_BOT_ALLOW_MOVE` | 1 | Разрешить движение |
| `TW_BOT_ALLOW_FIRE` | 1 | Разрешить стрельбу |
| `TW_BOT_ALLOW_HOOK` | 1 | Разрешить крюк |
| `TW_PUBLIC` | 0 | 0 — частный тестовый сервер; 1 — регистрация в master server |
| `TW_RCON_PASSWORD` | пусто | Пароль RCON — лучше задать явный сильный пароль |

После запуска подключайтесь клиентом Teeworlds 0.7.x к IP сервера, порт **8303/UDP**. Для игры через интернет откройте входящий UDP 8303 в firewall/роутере.

### Пользовательский конфиг

Если нужен полный контроль параметров, создайте `/config/server.cfg` в именованном томе `teeworlds-config`. При его наличии контейнер запускает игру только с ним, игнорируя переменные `TW_*`. При отсутствии этого файла параметры `TW_*` записываются в `/config/.generated-server.cfg` при каждом запуске.

### Локальная сборка

```bash
git clone --recursive https://github.com/mirivlad/teeworlds.git
cd teeworlds
docker build -t teeworlds-bots:local .
docker compose -f compose.yaml up -d
```

В примере compose используется GHCR-образ. Для запуска именно локальной сборки замените поле `image:` на `teeworlds-bots:local`.

### Статус

- Проверено: сборка сервера Linux amd64, карта dm1, 4 бота двигаются, подбирают предметы и сражаются.
- Требует проверки: подключение настоящего клиента и отработка освобождения слотов, карты CTF/TDM, устойчивость при длительной игре.
- Это экспериментальный мод, а не официальный релиз Teeworlds. Не рекомендуется публиковать сервер в интернете до дополнительных тестов.

Лицензии: [license.txt](license.txt) для движка и [datasrc/maps/license.txt](datasrc/maps/license.txt) для официальных карт.
