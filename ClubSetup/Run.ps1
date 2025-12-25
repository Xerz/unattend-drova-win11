#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$config = Import-PowerShellDataFile "C:\ClubSetup\config.psd1"

$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Join-Path $config.LogsRoot $ts
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Start-Transcript -Path (Join-Path $logDir "transcript.txt") -Force

function Write-Step($m){ Write-Host "==> $m" }

$statePath = "C:\ClubSetup\state.json"
if(Test-Path $statePath){
  $state = Get-Content $statePath -Raw | ConvertFrom-Json
}else{
  $state = [pscustomobject]@{ Phase = "Start" }
}

function Save-State($phase){
  $state.Phase = $phase
  ($state | ConvertTo-Json) | Set-Content -Encoding UTF8 $statePath
}

function Capture-Start {
  if(-not $config.CaptureMode){ return }
  Write-Step "Capture start (PSR + Procmon if exists)"
  $psrZip = Join-Path $logDir "psr.zip"
  Start-Process "$env:WINDIR\System32\psr.exe" -ArgumentList @("/start","/output",$psrZip,"/sc","1","/maxsc","200","/gui","0") | Out-Null

  $procmon = @("C:\ClubSetup\payload\Tools\Procmon64.exe","C:\ClubSetup\payload\Tools\Procmon.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
  if($procmon){
    $pml = Join-Path $logDir "procmon.pml"
    Start-Process $procmon -ArgumentList @("/accepteula","/quiet","/minimized","/backingfile",$pml) | Out-Null
  }
}

function Capture-Stop {
  if(-not $config.CaptureMode){ return }
  Write-Step "Capture stop"
  Start-Process "$env:WINDIR\System32\psr.exe" -ArgumentList "/stop" | Out-Null
  $procmon = @("C:\ClubSetup\payload\Tools\Procmon64.exe","C:\ClubSetup\payload\Tools\Procmon.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
  if($procmon){
    Start-Process $procmon -ArgumentList "/terminate" -Wait | Out-Null
  }
}

function Set-RegDword($Path, $Name, $Value) {
  if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
  New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
}

function Require-Reboot {
  Write-Step "Reboot required -> rebooting now"
  Save-State "AfterReboot"
  Capture-Stop
  Stop-Transcript
  shutdown.exe /r /t 0 /f
  exit
}

try {
  Capture-Start

  if($state.Phase -eq "Start"){
    Write-Step "Phase: Start"

    Write-Step "Rename computer if needed"
    if($env:COMPUTERNAME -ne $config.StationName){
      Rename-Computer -NewName $config.StationName -Force
      Require-Reboot
    }

    Write-Step "Prevent Windows Update from delivering drivers (WU GPU override protection)"
    Set-RegDword "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" "ExcludeWUDriversInQualityUpdate" 1

    Write-Step "Disable UAC (EnableLUA=0) (security tradeoff!)"
    Set-RegDword "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "EnableLUA" 0

    Write-Step "Power settings: never sleep/display off on AC"
    powercfg /change monitor-timeout-ac 0 | Out-Null
    powercfg /change standby-timeout-ac 0 | Out-Null
    powercfg /change hibernate-timeout-ac 0 | Out-Null

    Save-State "Drivers"
  }

  if($state.Phase -eq "Drivers"){
    Write-Step "Phase: Drivers (offline preferred)"

    Write-Step "Install chipset drivers via pnputil (INF)"
    if(Test-Path $config.ChipsetDriversDir){
      pnputil /add-driver "$($config.ChipsetDriversDir)\*.inf" /subdirs /install |
        Out-File (Join-Path $logDir "pnputil-chipset.txt") -Encoding UTF8
    } else {
      Write-Step "ChipsetDriversDir not found -> skip"
    }

    Write-Step "Install NVIDIA fixed version"
    if(Test-Path $config.NvidiaInstaller){
      Start-Process -FilePath $config.NvidiaInstaller -ArgumentList @("/s") -Wait
      "NVIDIA installer finished" | Out-File (Join-Path $logDir "nvidia.txt") -Encoding UTF8
    } else {
      Write-Step "NvidiaInstaller not found -> skip"
    }

    Write-Step "Now you can connect Ethernet / enable Internet, then reboot to continue updates/apps."
    Save-State "Updates"
    Require-Reboot
  }

  if($state.Phase -eq "Updates"){
    Write-Step "Phase: Updates (PSWindowsUpdate)"

    Write-Step "Install PSWindowsUpdate module"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-PackageProvider -Name NuGet -Force -Scope AllUsers | Out-Null
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

    if(-not (Get-Module -ListAvailable -Name PSWindowsUpdate)){
      Install-Module PSWindowsUpdate -Force -Scope AllUsers
    }
    Import-Module PSWindowsUpdate

    Write-Step "Enable Microsoft Update (optional) + run update loop"
    try { Add-WUServiceManager -MicrosoftUpdate -Confirm:$false | Out-Null } catch {}

    $round = 0
    while($true){
      $round++
      Write-Step "WU round $round: searching..."
      $list = Get-WindowsUpdate -MicrosoftUpdate -IgnoreUserInput -ErrorAction SilentlyContinue
      if(-not $list){
        Write-Step "No updates found."
        break
      }

      Write-Step "Installing updates (can reboot)..."
      Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot |
        Out-File (Join-Path $logDir "pswindowsupdate-round-$round.txt") -Encoding UTF8

      if(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"){
        Save-State "Updates"
        Require-Reboot
      }
    }

    Save-State "Apps"
  }

  if($state.Phase -eq "Apps"){
    Write-Step "Phase: Apps (winget import)"

    if(Get-Command winget.exe -ErrorAction SilentlyContinue){
      winget source update | Out-Null

      if(Test-Path $config.WingetImportJson){
        winget import -i $config.WingetImportJson --accept-source-agreements --accept-package-agreements --disable-interactivity |
          Out-File (Join-Path $logDir "winget-import.txt") -Encoding UTF8
      } else {
        Write-Step "apps.json not found -> put it at C:\ClubSetup\apps.json or change config"
      }
    } else {
      Write-Step "winget not found -> skip (check App Installer)"
    }

    Save-State "Remote"
  }

  if($state.Phase -eq "Remote"){
    Write-Step "Phase: Remote (VDD + Sunshine + Autologon)"

    if(Test-Path $config.VddXmlSource){
      New-Item -ItemType Directory -Force (Split-Path $config.VddXmlTarget) | Out-Null

      [xml]$x = Get-Content $config.VddXmlSource -Raw

      $resNodes = @($x.vdd_settings.resolutions.resolution)
      function Has-Res($w,$h){
        $resNodes | Where-Object { $_.width -eq "$w" -and $_.height -eq "$h" } | Select-Object -First 1
      }
      function Add-Res($w,$h,$rr=30){
        $n = $x.CreateElement("resolution")
        $wEl = $x.CreateElement("width");  $wEl.InnerText = "$w"
        $hEl = $x.CreateElement("height"); $hEl.InnerText = "$h"
        $rEl = $x.CreateElement("refresh_rate"); $rEl.InnerText = "$rr"
        $n.AppendChild($wEl) | Out-Null
        $n.AppendChild($hEl) | Out-Null
        $n.AppendChild($rEl) | Out-Null
        $x.vdd_settings.resolutions.AppendChild($n) | Out-Null
      }

      if(-not (Has-Res 2560 1600)){ Add-Res 2560 1600 30 }

      $resNodes = @($x.vdd_settings.resolutions.resolution)
      $main = $resNodes | Where-Object { $_.width -eq "1920" -and $_.height -eq "1080" } | Select-Object -First 1
      if($main){
        $null = $x.vdd_settings.resolutions.RemoveChild($main)
        $null = $x.vdd_settings.resolutions.PrependChild($main)
      }

      $x.Save($config.VddXmlTarget)
      "VDD xml deployed -> $($config.VddXmlTarget)" | Out-File (Join-Path $logDir "vdd.txt") -Encoding UTF8
    } else {
      Write-Step "VddXmlSource not found -> skip"
    }

    $sun = Get-Command sunshine -ErrorAction SilentlyContinue
    if($sun){
      & $sun.Source --creds $config.SunshineUser $config.SunshinePassword
      "Sunshine creds set" | Out-File (Join-Path $logDir "sunshine.txt") -Encoding UTF8
    } else {
      Write-Step "sunshine not found in PATH -> install via winget or add to PATH"
    }

    $auto = Get-Command autologon -ErrorAction SilentlyContinue
    if(-not $auto){
      $autoPath = "C:\ClubSetup\payload\Tools\Autologon.exe"
      if(Test-Path $autoPath){ $auto = [pscustomobject]@{ Source = $autoPath } }
    }
    if($auto){
      $domain = $env:COMPUTERNAME
      Start-Process -FilePath $auto.Source -ArgumentList @(
        "/accepteula", $config.LocalUser, $domain, $config.LocalUserPassword
      ) -Wait
      "Autologon enabled for $($config.LocalUser)" | Out-File (Join-Path $logDir "autologon.txt") -Encoding UTF8
    } else {
      Write-Step "Autologon.exe not found -> skip"
    }

    Save-State "Drova"
  }

  if($state.Phase -eq "Drova"){
    Write-Step "Phase: Drova (MSI + reg + tasks XML)"

    if(Test-Path $config.DrovaMsi){
      Start-Process msiexec.exe -ArgumentList @("/i",$config.DrovaMsi,"/qn","/norestart") -Wait
    }
    if(Test-Path $config.DrovaReg){
      reg import $config.DrovaReg | Out-Null
    }

    $userId = "$($env:COMPUTERNAME)\$($config.LocalUser)"
    $patchPath = "C:\Drova\Patches\Patch.ps1"
    $tmp = Join-Path $env:TEMP "drova-task.xml"

    foreach($name in @("DrovaApplyPatches","DrovaReboot")){
      $src = Join-Path $config.TasksDir ($name + ".xml")
      if(Test-Path $src){
        $xml = Get-Content $src -Raw
        $xml = $xml -replace "\[\[Нужно будет сменить после импорта на игрового пользователя\]\]", $userId
        $xml = $xml -replace "\[\[Полный путь до патча\]\]", (Split-Path $patchPath)
        Set-Content -Path $tmp -Value $xml -Encoding Unicode
        schtasks /Create /TN $name /XML $tmp /F | Out-File (Join-Path $logDir "schtasks-$name.txt") -Encoding UTF8
      }
    }

    Save-State "Finalize"
  }

  if($state.Phase -eq "Finalize"){
    Write-Step "Phase: Finalize (pause updates for years)"

    $pauseDays = [int]($config.PauseUpdatesYears * 365)
    $pause = (Get-Date).AddDays($pauseDays).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $pause_start = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $wu = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
    if (-not (Test-Path $wu)) { New-Item $wu -Force | Out-Null }

    Set-ItemProperty -Path $wu -Name 'PauseUpdatesExpiryTime' -Value $pause
    Set-ItemProperty -Path $wu -Name 'PauseFeatureUpdatesStartTime' -Value $pause_start
    Set-ItemProperty -Path $wu -Name 'PauseFeatureUpdatesEndTime' -Value $pause
    Set-ItemProperty -Path $wu -Name 'PauseQualityUpdatesStartTime' -Value $pause_start
    Set-ItemProperty -Path $wu -Name 'PauseQualityUpdatesEndTime' -Value $pause
    Set-ItemProperty -Path $wu -Name 'PauseUpdatesStartTime' -Value $pause_start

    Save-State "Done"
    Write-Step "DONE. Logs: $logDir"
    Write-Step "Remaining manual: Parsec login + game warm-up when needed."
  }

}
finally {
  Capture-Stop
  Stop-Transcript
}
