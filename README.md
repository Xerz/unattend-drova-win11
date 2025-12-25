# unattend-drova-win11

Набор файлов для автоматической установки и первичной настройки Windows 11 через `autounattend.xml` + PowerShell.

## Структура флешки (Ventoy)

```
\ISO\Win11.iso
\autounattend.xml
\ClubSetup\
  Run.ps1
  config.psd1
  vdd_settings.xml
  tasks\
    DrovaApplyPatches.xml
    DrovaReboot.xml
  payload\
    Nvidia\NVIDIA_581.80.exe
    Chipset\*.inf
    Drova\drovaWindowsMerchantInstaller.msi
    Drova\Drova.reg
    Tools\Procmon64.exe
    Tools\Autologon.exe
  layout\
    TaskbarPins.xml
    LayoutModification.json
```

> **Важно:** third-party EXE/MSI в репозиторий не кладём. Они должны лежать в папках `ClubSetup\payload\...` как показано выше.

## Что где лежит (third-party файлы)

Положите внешние установщики/утилиты в такие пути:

- `ClubSetup\payload\Nvidia\NVIDIA_581.80.exe` — установщик NVIDIA.
- `ClubSetup\payload\Chipset\` — INF-пакеты чипсета.
- `ClubSetup\payload\Drova\drovaWindowsMerchantInstaller.msi` — установщик Drova.
- `ClubSetup\payload\Drova\Drova.reg` — реестр Drova (если нужен).
- `ClubSetup\payload\Tools\Procmon64.exe` — Procmon (опционально, для логов).
- `ClubSetup\payload\Tools\Autologon.exe` — Autologon (опционально, если не ставите через winget).

## Быстрый старт

1. Заполните `autounattend.xml` и `ClubSetup/config.psd1`:
   - имя ПК,
   - пароли локального пользователя/Autologon/Sunshine.
2. Скопируйте `ClubSetup` и `autounattend.xml` на флешку, как в структуре выше.
3. Установите Windows **без интернета** — скрипт сам поставит драйверы и попросит ребут.
4. Подключите Ethernet после шага драйверов — далее пойдут WU + winget + Sunshine + Drova.

## Что делает скрипт

`ClubSetup/Run.ps1`:

- ведёт логи (Transcript + PSR + Procmon при наличии);
- ставит драйверы чипсета и NVIDIA;
- гоняет Windows Update через PSWindowsUpdate;
- ставит приложения через `winget import` (если есть `apps.json`);
- настраивает VDD (копия XML + гарантии по разрешениям);
- задаёт креды Sunshine;
- включает Autologon (если есть `Autologon.exe`);
- ставит Drova + импортирует XML-задачи;
- ставит «pause updates» на годы.

## Конфиг

См. `ClubSetup/config.psd1`. Основные параметры:

- `StationName`
- `LocalUser` / `LocalUserPassword`
- `SunshineUser` / `SunshinePassword`
- `PauseUpdatesYears`
- пути к драйверам/инсталляторам/задачам.

## Заметки

- Если в новых билдах Windows 11 OOBE всё равно требует аккаунт онлайн — используйте fallback с `start ms-cxh:localonly`.
- Настройка Taskbar/Start pin’ов зависит от выбранного способа деплоя (LGPO/PPKG/ручной GPO). Файлы можно положить в `ClubSetup/layout`.
