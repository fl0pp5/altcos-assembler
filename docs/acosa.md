# Документация по работе со сборщиком

`acosa.py` (ALT Container OS Assembler) - запускает сборку из конфига

# Спецификация acosa-конфига
- `variables` (list of objects) - глобальные переменные
  - `name` (string) - название переменной
  - `value` (string) - значение
  - `export` (bool) - экспортировать переменную перед вызовом сервиса
  - `command` (bool) - если поле равно `true`, значение из `value` будет восприниматься как команда, результат которой будет записан в `value`

- `services` (list of objects) - список сервисов для запуска
  - `name` (string) - название сервиса (доступные сервисы можно посмотреть в директории `scripts`, например `init-base.sh`)
  - `args` (list of objects) - аргументы, которые принимает сервис (узнать допустимые аргументы можно при помощи ключа `-a|--api`, e.g. `./scripts/init-base -a`)
  - `with_print` (bool) - выводить stdout/stderr на экран
  - `as_root` (bool) - выполнять сервис от имени `root`, для работы этой секции необходимо определить переменную `PASSWORD`, где указан ваш пароль от админа
  - `skip` (bool) - пропустить текущий сервис
  - `variables` (list of objects) - локальные переменные сервиса (задаются аналогично глобальным)
  WARNING: если глобальная переменная изменилась в сервисе, эти изменения сохранятся

# Пример работы acosa.py
На вход `acosa.py` принимает yaml-конфиг, для примера создадим qcow2 образ

```yaml
# altcos.yaml
variables:
- name: stream
  value: altcos/x86_64/sisyphus/base
- name: repo_root
  value: "echo -n `pwd`/repo"
  command: true
- name: storage
  value: "echo -n `pwd`/storage"
  command: true
- name: mode
  value: "bare"

services:
- name: init-base.sh
  args:
    stream: "$stream"
    repo_root: "$repo_root"

- name: get-rootfs.sh
  variables:
  - name: mkimage_root
    value: "echo -n `pwd`/mkimage-profiles"
    command: true
  args:
    stream: "$stream"
    repo_root: "$repo_root"
    mkimage_root: "$mkimage_root"

- name: convert-rootfs.sh
  args:
    stream: $stream
    repo_root: $repo_root
    mode: $mode
    url: "https://altcos.altlinux.org"
    message: "initial commit"
  as_root: true

- name: build-qcow2.sh
  args:
    stream: $stream
    repo_root: $repo_root
    mode: $mode
    storage: $storage
    commit: latest
  as_root: true
```

Запуск

```sh
./acosa.py altcos.yaml
```