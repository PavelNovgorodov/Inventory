<#
    Сбор инвентаризационной информации
    Модуль сбора значения в реестре пользователя

    Наименование типа инвентаризационой информации - не удалять!

    <Description>Значения ключей реестра</Description>

    
    Сбор значений параметров ключей реестра.
    Могут быть собраны значения всех параметров и вложенных ключей или значение конкретного параметра ключа реестра.
    Настройка сбора осуществляется через передачу дополнительного параметра в модуль reg.ps1 через параметр запуска -ModuleParameters командлета Start-Inventory.

    Например,

        $Parameters = @(
                        @{
                            Module = "reg";
                            VarName = "Reg";
                            VarValue = @(
                                            @{HKey = "HKEY_CURRENT_USER"; Key = "SOFTWARE\Microsoft\Windows\CurrentVersion\Run"}, #собрать все значения включая вложенные ключи
                                            @{HKey = "HKEY_CURRENT_USER"; Key = "SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"}, #собрать все значения включая вложенные ключи
                                            @{HKey = "HKEY_USERS"; Key = "SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings"; ValueName = "AutoConfigURL"} #собрать значение параметра AutoConfigURL
                                         )
                         }
                       )
        #запуск командлета
        Start-Inventory -StartType InvRemote -ModuleParameters $Parameters
    
        Использумые ключи хэш таблицы:
        HKey - раздел реестра ("HKEY_USERS", "HKEY_LOCAL_MACHINE", "HKEY_CURRENT_USER", "HKEY_CLASSES_ROOT", "HKEY_CURRENT_CONFIG")
        Key - наименование ключа (строка)
        ValueName - наменование параметра (строка)

    Передача параметра:
    $Parameters = @(
                        VarName = "Reg", 
                        VarValue = @(
                                        @{HKey = ""; Key = ""; ValueName = ""}, 
                                        @{HKey = ""; Key = ""; ValueName = ""},
                                        @{HKey = ""; Key = ""; ValueName = ""}
                                    )
                   )
#>

#возможные варианты использования наименований ключей реестра
$HKeyName1 = "HKEY_USERS"
$HKeyName2 = ("HKEY_LOCAL_MACHINE", "HKEY_CURRENT_USER", "HKEY_CLASSES_ROOT", "HKEY_CURRENT_CONFIG")

#получаем имя текущей функции (имя функции Get-Inv-ххх), из него тип собираемой информации
$CurrnetTypeInfo = ($MyInvocation.MyCommand.Name -split "-")[-1]

#обработка дополнительных параметров модуля
#получаем значение параметра Reg
$ParamReg = ($global:MParameters | Where-Object {$_["Module"] -eq "reg" -and $_["VarName"] -eq "Reg"}).VarValue

#если значениe параметра не получено завершаем
if (!$ParamReg)
{
    Write-Host "Не заданы параметры сбора для модуля reg"
    return
 }

<#
    Получение значений ключа реестра в том числе дочерних ключей.
    Если задан параметр ValueName - получается только значение заданного параметра.
#>
function Get-RegistryValues {
    Param (
            [string]$KeyPath,
            [string]$ValueName,
            [string]$ComputerName
    )

#текст получение всех параметров ключа включая вложенные
$ScriptTextAll = @"
param(`$KeyPath)
    `$r = Get-ChildItem -Path "Registry::`$KeyPath" -Recurse -ErrorAction SilentlyContinue
    `$r = `$r | ForEach-Object {
    `$key = `$_
    try {
            `$properties = Get-ItemProperty -Path `$key.PSPath -ErrorAction Stop
            `$properties.PSObject.Properties |`
                                                Where-Object {`$_.MemberType -eq 'NoteProperty' -and `$_.Name -notin @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')} |`
                                                ForEach-Object {
                                                                    [PSCustomObject]@{
                                                                                        KeyPath   = `$(`$key.PSPath -replace "^[^:]*::", "")
                                                                                        ValueName = `$_.Name
                                                                                        Value     = `$_.Value
                                                                                     }
                                                               }
        }
        catch {}
        }
    `$r
"@

#текст получение конкретного значения ключа
$ScriptTextOnlyValue = @"
param(`$KeyPath, `$ValueName)

if ([bool](Get-ItemProperty "Registry::`$KeyPath" -Name `$ValueName -ErrorAction SilentlyContinue)) 
{

    `$r = Get-ItemProperty -Path "Registry::`$KeyPath" -ErrorAction Stop
    [PSCustomObject]@{
                        KeyPath   = `$(`$r.PSPath -replace "^[^:]*::", "")
                        ValueName = `$ValueName
                        Value     = `$r.`$ValueName
                    }
}
else
{
    Write-Host "На найдено ключ - значение: `$KeyPath - `$ValueName" 
}
"@

    #если передано имя параметра - используем скрипт для получения значения конкретного параметра
    if ($ValueName)
    {
        $ScriptBlock = [scriptblock]::Create($ScriptTextOnlyValue)
    }
    else
    {
        $ScriptBlock = [scriptblock]::Create($ScriptTextAll)
    }

    #локальный компьютер
    $LocalComputer = $ComputerName -eq $env:COMPUTERNAME

    #получаем содержимое ключа
    if ($LocalComputer)
    {
        $r = Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $KeyPath, $ValueName

    }
    else
    {
        $r = Invoke-Command -ComputerName $ComputerName -ScriptBlock $ScriptBlock -ArgumentList $KeyPath, $ValueName
    }

    $r = $r | select @{Name="ComputerName"; expression={$ComputerName}},`
                     KeyPath, `
                     ValueName,`
                     Value, `
                     @{Name="CollectionDate"; expression={$collection_date}},`
                     @{Name="TypeInfo"; expression={$CurrnetTypeInfo}}

    return $r
} #function


<#
    Получение значений куста HKEY_USERS
    В связи с тем что в нем содержатся профили пользователей, первоначально получается перечень профилей пользователей на компьютер.
    Далее определяется значения для ключа для всех пользователей профили которых определены на компьютере и они были активны в течении 30 дней.
#>
function GetHKEY_USERS {
    Param (
            [string]$ComputerName,
            [string]$HKey,
            [string]$Key,
            [string]$ValueName
    )

    $r = @()

    #дата последнего использования профиля пользователем
    $LastDateUseProfile = (Get-Date).AddMonths(-1)

    #профили пользователей на компьютере
    $UsersProfile = Get-WmiClass -ComputerName $ComputerName -ClassName "Win32_UserProfile" -cimSession $cimSession -PSver $PSver
    
    #получаем перечень профилей активных в течении 30 дней, и только для доменных пользователей
    $UsersProfile = $UsersProfile | Where-Object {$_.lastusetime -ne $null} |`
                                    Select SID, `
                                           @{Name="UserName"; expression={([System.Security.Principal.SecurityIdentifier]$_.SID).Translate([System.Security.Principal.NTAccount]).Value}},`
                                           @{Name="LastUseTime"; Expression={
                                                                                if ($_.lastusetime.length -eq 1)
                                                                                {
                                                                                    $_.lastusetime
                                                                                }
                                                                                else
                                                                                {
                                                                                    $_.ConvertToDateTime($_.lastusetime)
                                                                                }
                                                                             }
                                            } | Where-Object -FilterScript {$_.UserName -Like "$env:USERDOMAIN*" -and $_.LastUseTime -gt $LastDateUseProfile}

    #цикл по пользователям
    foreach($user in $UsersProfile) {

        $KeyPath = "$($HKey)\$($user.SID)\$Key"

        $KeyValue = Get-RegistryValues -ComputerName $ComputerName -KeyPath $KeyPath -ValueName $ValueName

        if (!([string]::IsNullOrWhiteSpace($KeyValue)))
        {

            $r += $KeyValue | select ComputerName,`
                                   @{Name="KeyPath"; expression={"[$($user.UserName)] $KeyPath"}},`
                                   ValueName,`
                                   Value, `
                                   CollectionDate,`
                                   TypeInfo
        }
    } #foreach


    return $r
} #function

$result = @()

#цикл по значениям массива параметров - HKey\Key\ValueName
foreach ($reg in $ParamReg)
{
    $HKey = $reg.HKey
    $Key = $reg.Key
    $ValueName = $reg.ValueName


    #разные варинаты в зависимости от HKey
    switch ($HKey)
    {
        $HKeyName1 {$result += GetHKEY_USERS -ComputerName $ComputerName -HKey $HKey -Key $Key -ValueName $ValueName}

        {$_ -in ($HKeyName2)} {$result += Get-RegistryValues -ComputerName $ComputerName  -KeyPath "$($HKey)\$Key" -ValueName $ValueName}

        default { Write-Host "Не верно задан ключ реестра $_. Допустимые варианты:  $HKeyName1, $($HKeyName2 -join ",")"}
    }
}


if (!$result) {$result = $null}
$result = [pscustomobject]@{Type = $CurrnetTypeInfo; Data = $result}

return $result
