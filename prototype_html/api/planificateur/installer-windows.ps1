# SIGH-CNT — installe la tâche planifiée du serveur (Windows), toutes les 5 minutes.
# Usage (PowerShell en administrateur) :
#   .\installer-windows.ps1 -Racine "C:\laragon\www\sigh" -Php "C:\laragon\bin\php\php-8.3\php.exe"
# Rejouable : une tâche du même nom est remplacée.
param(
  [Parameter(Mandatory = $true)][string]$Racine,
  [string]$Php = "php.exe",
  [string]$Nom = "SIGH-CNT-planificateur"
)
$cron = Join-Path $Racine "api\cron.php"
if (-not (Test-Path $cron)) { Write-Error "api\cron.php introuvable sous $Racine"; exit 1 }
$action  = New-ScheduledTaskAction -Execute $Php -Argument "`"$cron`"" -WorkingDirectory $Racine
$declen  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$reglage = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 4)
Register-ScheduledTask -TaskName $Nom -Action $action -Trigger $declen -Settings $reglage -User "SYSTEM" -RunLevel Highest -Force | Out-Null
Write-Host "Tâche '$Nom' installée : $Php `"$cron`" toutes les 5 minutes."
Write-Host "Vérification : & `"$Php`" `"$cron`" --force   (puis écran « Tâches planifiées », M14)"
