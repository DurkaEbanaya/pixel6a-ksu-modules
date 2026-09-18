# Модули KSU для Pixel 6a

**[English](README.md) | Русский**

Автономные модули [KernelSU](https://kernelsu.org)/[KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) для личного устройства **Pixel 6a** с рут-доступом.

Разработано и проверено в закрытой лабораторной среде (Pixel 6a, Android 16, сборка CP1A.260405.005, ядро 6.1.145). Модули — обычные shell-скриптовые KSU-модули: без кода ядра, без эксплойтов, без посторонних бинарников.

## Модули

### DeVerizonficator v1.0
Разблокирует не-Verizon SIM на Verizon-версиях Pixel 6a.

На Verizon-устройствах операторская блокировка SIM реализована профилем carrier-restriction, который провиженится сервисом zero-touch-провижининга Google, кэшируется на устройстве и применяется при каждой загрузке — любая не-Verizon SIM определяется как `CARDSTATE_RESTRICTED` (только экстренные вызовы). Модуль при каждой загрузке удаляет кэшированный профиль из настроек приложения-провижинера, после чего его штатный fallback применяет режим **all-carriers-allowed**.

Проверено живьём: радиолог меняется с `SET_ALLOWED_CARRIERS allowed:[Verizon...] default:НЕ-РАЗРЕШЕНО → CARDSTATE_RESTRICTED` на `SET_ALLOWED_CARRIERS allowed:[] default:РАЗРЕШЕНО → CARDSTATE_PRESENT`.

Не изменяет прошивку модема, EFS/NV, операторские аккаунты и биллинг.

### DeGoogleupdatetificator v1.0 (id модуля — `noota`)
Полностью блокирует автоматические системные (OTA) обновления: отключает точечные OTA-компоненты Google Play Services (`.update.SystemUpdateService`, `.update.SystemUpdateActivity`, `.update.SystemUpdateGcmTaskService`, `.update.SystemUpdatePersistentListenerService`, `.update.OtaSuggestionActivity`, `.update.UpdateFromSdCardActivity`, `.update.UucNotificationReceiverService`), выставляет флаг политики `ota_disable_automatic_update` и best-effort останавливает `update_engine` на текущую загрузку.

По задумке не затронуты: сами GMS/Play Store, Mainline (Google Play system updates), операторский OMADM, `configupdater`. **Полностью обратимо**: при удалении модуля восстанавливается настройка и включаются компоненты.

⚠️ Блокировка OTA также блокирует обновления безопасности Android — следить за патчами придётся самостоятельно.

## Требования

- Лично принадлежащий Pixel 6a (или совместимое устройство) **с уже имеющимся рутом**
- KernelSU / KernelSU-Next (или любой Magisk-совместимый загрузчик модулей)
- Рабочий путь восстановления на случай проблем

## Установка

Через менеджер KernelSU: установите ZIP из релиза.
Из root-шелла:

```sh
ksud module install deverizonficator-v1.0.zip
```

Перезагрузите устройство. Каждый модуль пишет лог в каталог модуля
(`/data/adb/modules/<id>/*.log`) — проверьте его, чтобы убедиться, что применено.

## Удаление

Удалите через менеджер KernelSU (или `ksud module uninstall <id>`).
Оба модуля при удалении восстанавливают изменённое состояние.

## Ограничения

- Проверено только на указанной сборке; имена компонентов и настройки могут меняться между версиями Android и GMS.
- DeVerizonficator работает, потому что блокировка на этом устройстве применялась на уровне Android-framework — модуль не может снять модемную/NV-персонализацию, если она существует на других устройствах.
- Никаких гарантий. Используете модули на свой страх и риск.

## Ответственное использование

Используйте только на устройствах, которые вам принадлежат или администрирование которых вам разрешено. Соблюдайте условия оператора связи, политики устройства, применимое законодательство и условия Google.

## Благодарности

- [KernelSU](https://kernelsu.org) / [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) — экосистема модулей.
- Метамодуль [meta-overlayfs](https://github.com/KernelSU-Modules-Repo/meta-overlayfs) — использовался в тестовой конфигурации при разработке.

## Лицензия

[GPL-3.0-or-later](LICENSE)
