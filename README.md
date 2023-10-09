[![alt-logo](res/alt-logo.png)](https://www.altlinux.org/)

# ALT Container OS Assembler (ALTCOS Assembler)

Инструменты для создания и сопровождения `ALTCOS` репозитория 

# Подготовка
Установка зависимостей и настройка submodules
```sh
make all
```

Для подписи образов нужно сгенерировать ключ
```sh
openssl genrsa -out private_altcos.pem 2048
```

Для некоторых сервисов необходимы root-права, для этого нужно экспортировать пароль

Создайте скрипт содержащий пароль:
```sh
# export_password.sh
export PASSWORD="..."
```
```sh
source export_password.sh
```
<span style="color:red">**Если вы экспортировали пароль интерактивно - почистите за собой историю!**</span>


# Дополнительно
- [Спецификация acosa-файла](docs/acosa.md)
- [О сервисах](docs/services.md)
- [Примеры](examples/)
