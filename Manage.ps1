$ErrorActionPreference='Stop'
$serviceName='zapret-pubg-discord'
$packageId='pubg-discord-zapret-20261018'
$packageRoot=$env:ZAPRET_PACKAGE_ROOT
$targetRoot=Join-Path $env:ProgramData 'PUBG-Discord-Zapret'
$action=$env:ZAPRET_PACKAGE_ACTION
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=New-Object Security.Principal.WindowsPrincipal($identity)
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Требуются права администратора.'}
if(-not [Environment]::Is64BitOperatingSystem){throw 'Этот комплект предназначен для Windows x64.'}
if($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64'){throw 'Нужна Windows x64 на Intel/AMD; ARM64 не поддерживается этим драйвером.'}
$service=Get-Service $serviceName -ErrorAction SilentlyContinue
if($service){
 $image=(Get-ItemProperty ("HKLM:\SYSTEM\CurrentControlSet\Services\"+$serviceName)).ImagePath
 $expected='"'+(Join-Path $targetRoot 'bin\winws.exe')+'" '
 if(-not $image.StartsWith($expected,[StringComparison]::OrdinalIgnoreCase)){throw 'Служба с таким именем принадлежит другой установке. Она не изменена.'}
}
if($action -eq 'remove'){
 if($service){
  Stop-Service $serviceName
  & sc.exe delete $serviceName | Out-Null
  if($LASTEXITCODE -ne 0){throw 'Не удалось удалить службу.'}
 }
 Write-Host 'Zapret остановлен, его автозапуск удалён.' -ForegroundColor Green
 Write-Host ('Копия файлов сохранена для повторной установки: '+$targetRoot)
 return
}
if($action -ne 'install'){throw 'Неизвестная операция.'}
$others=@(Get-CimInstance Win32_Service | Where-Object {$_.Name -ne $serviceName -and $_.PathName -match 'winws\.exe'})
if($others.Count){throw ('Найдена другая служба zapret: '+(($others|ForEach-Object Name)-join ', ')+'. Удалите старую установку перед запуском этого комплекта.')}
$ownPid=if($service){(Get-CimInstance Win32_Service -Filter "Name='$serviceName'").ProcessId}else{0}
$otherProcesses=@(Get-CimInstance Win32_Process -Filter "Name='winws.exe'" | Where-Object ProcessId -ne $ownPid)
if($otherProcesses.Count){throw 'Закройте другие запущенные батники zapret и повторите установку. Они не остановлены автоматически.'}
$manifest=Get-Content -LiteralPath (Join-Path $packageRoot 'SHA256.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($entry in $manifest.PSObject.Properties){
 $relative=[string]$entry.Name
 if($relative -match '(^[\\/]|:|(^|[\\/])\.\.([\\/]|$))'){throw 'Недопустимый путь в списке файлов.'}
 $file=Join-Path $packageRoot $relative
 if(-not(Test-Path -LiteralPath $file)){throw ('Не найден файл: '+$relative+'. Извлеките ZIP целиком.')}
 if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $entry.Value){throw ('Файл повреждён или изменён: '+$relative)}
}
$template=[IO.File]::ReadAllText((Join-Path $packageRoot 'arguments-template.txt'),[Text.Encoding]::UTF8)
if(-not $template.Contains('{{ROOT}}') -or $template -match '(?i)[a-z]:\\users\\|\.ssh[\\/]|--debug='){throw 'Шаблон параметров не прошёл проверку.'}
$oldImage=if($service){$image}else{$null}
$wasRunning=$service -and $service.Status -eq 'Running'
$backup=$null
$newService=$false
try {
 if(Test-Path -LiteralPath $targetRoot){
  $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
  $backup=Join-Path $env:ProgramData ('PUBG-Discord-Zapret-backup-'+$stamp)
  New-Item -ItemType Directory -Path $backup | Out-Null
  $backupAcl=Get-Acl $backup
  $backupAcl.SetSecurityDescriptorSddlForm('O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)')
  Set-Acl $backup $backupAcl
  Get-ChildItem -LiteralPath $targetRoot | Copy-Item -Destination $backup -Recurse -Force
 }
 if($service){Stop-Service $serviceName}
 New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
 $acl=Get-Acl -LiteralPath $targetRoot
 $acl.SetSecurityDescriptorSddlForm('O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)')
 Set-Acl -LiteralPath $targetRoot -AclObject $acl
 foreach($folder in @('bin','lists')){
  $sourceDir=Join-Path $packageRoot $folder
  Get-ChildItem -LiteralPath $sourceDir -Recurse -File|ForEach-Object {
   $relative=$_.FullName.Substring($packageRoot.TrimEnd('\').Length).TrimStart('\')
   $destination=Join-Path $targetRoot $relative
   New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force|Out-Null
   if(-not(Test-Path -LiteralPath $destination) -or (Get-FileHash -LiteralPath $_.FullName).Hash -ne (Get-FileHash -LiteralPath $destination).Hash){
    Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
   }
  }
 }
 # Runtime code is writable only by Administrators and SYSTEM, including existing files.
 Get-ChildItem -LiteralPath $targetRoot -Recurse|ForEach-Object {
  $fileAcl=Get-Acl -LiteralPath $_.FullName
  $sddl=if($_.PSIsContainer){'O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'}else{'O:BAG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)'}
  $fileAcl.SetSecurityDescriptorSddlForm($sddl)
  Set-Acl -LiteralPath $_.FullName -AclObject $fileAcl
 }
 foreach($entry in $manifest.PSObject.Properties|Where-Object {$_.Name -match '^(bin|lists)/'}){
  if((Get-FileHash -LiteralPath (Join-Path $targetRoot $entry.Name)).Hash -ne $entry.Value){throw ('Копия файла не прошла проверку: '+$entry.Name)}
 }
 $arguments=$template.Replace('{{ROOT}}',$targetRoot).Trim()
 $exe=Join-Path $targetRoot 'bin\winws.exe'
 $command='"'+$exe+'" '+$arguments
 if($service){
  $change=Invoke-CimMethod -InputObject (Get-CimInstance Win32_Service -Filter "Name='$serviceName'") -MethodName Change -Arguments @{PathName=$command;StartMode='Automatic'}
  if($change.ReturnValue -ne 0){throw ('Не удалось обновить службу: '+$change.ReturnValue)}
 }else{
  New-Service -Name $serviceName -DisplayName 'zapret - PUBG and Discord' -BinaryPathName $command -StartupType Automatic | Out-Null
  $newService=$true
 }
 Set-Service $serviceName -Description 'Discord and PUBG UDP 7000-7999; local DPI processing without VPN.'
 Start-Service $serviceName
 Start-Sleep -Seconds 2
 if((Get-Service $serviceName).Status -ne 'Running'){throw 'Служба не запустилась.'}
 & sc.exe failure $serviceName reset= 86400 actions= restart/3000/restart/5000/restart/10000 | Out-Null
 [pscustomobject]@{PackageId=$packageId;Installed=(Get-Date).ToString('o');Service=$serviceName;Arguments=$arguments;Profile='PUBG fake TTL5 repeats6 cutoff n3 + Discord';Backup=$backup}|ConvertTo-Json -Depth 3|Set-Content (Join-Path $targetRoot 'package.json') -Encoding UTF8
 Write-Host 'Готово. PUBG и Discord настроены. Автозапуск включён.' -ForegroundColor Green
 Write-Host 'Полностью перезапустите PUBG и Discord. VPN для этого комплекта не нужен.'
}catch{
 $reason=$_.Exception.Message
 Stop-Service $serviceName -ErrorAction SilentlyContinue
 if($newService){& sc.exe delete $serviceName|Out-Null}
 if($backup){Get-ChildItem -LiteralPath $backup|Copy-Item -Destination $targetRoot -Recurse -Force}
 if($oldImage){
  $restored=Invoke-CimMethod -InputObject (Get-CimInstance Win32_Service -Filter "Name='$serviceName'") -MethodName Change -Arguments @{PathName=$oldImage}
  if($restored.ReturnValue -ne 0){Write-Warning ('Не удалось восстановить параметры службы: '+$restored.ReturnValue)}
  if($wasRunning){Start-Service $serviceName}
 }
 throw ('Установка не завершена: '+$reason)
}
