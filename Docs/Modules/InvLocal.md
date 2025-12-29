## Локальный сбор - InvLocal.ps1

```mermaid
flowchart LR
    Start[Старт]
    InputParam[/"Входные параметры:
               InvLocalComputer
               InvLocalCompressFile
               InvTypeSelect
               InvLocalDaysOld
               ExtendLog"/]
    InvTypeSelect[[Обработка параметра InvTypeSelect]]
    CheckInvFiles{Данные инвентаризации в каталоге InvLocalComputers устарели?}
    DeleteInvFiles(Удаляем файлы инвентаризации)
    StartInv[["Запускаем процесс сбора инвентаризации
               Get-Inventory.ps1"]]
    CheckInv{Данные получены?}
    SaveInv[/Сохраняем данные в каталог InvLocalComputers/]
    CheckZip{Параметр InvLocalCompressFile задан?}
    CreateZip[/Упаковываем файлы из каталога InvLocalComputers в ZIP в каталог InvLocalCompressFile/]
    Finish[Финиш]

    Start --> InputParam
    InputParam --> InvTypeSelect
    InvTypeSelect --> CheckInvFiles
    CheckInvFiles --> |Да| DeleteInvFiles
        DeleteInvFiles --> StartInv
            StartInv --> CheckInv
            CheckInv --> |Да| SaveInv
                SaveInv --> CheckZip
                    CheckZip --> |Да| CreateZip
                        CreateZip --> Finish
                    CheckZip --> |Нет| Finish
            CheckInv --> |Нет| Finish
    CheckInvFiles --> |Нет| Finish
```

**Ссылки:**
- [Обработка параметра InvTypeSelect - SelectInvType.ps1](SelectInvType.md)
- [Описание входных параметров ../README.md](../../README.md#параметры-запуска-командлета)
