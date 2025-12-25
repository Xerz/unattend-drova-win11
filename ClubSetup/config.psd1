@{
  StationName       = "DROVA-001"
  LocalUser         = "drover"
  LocalUserPassword = "CHANGE_ME_STRONG_PASSWORD"

  SunshineUser      = "sunshine"
  SunshinePassword  = "CHANGE_ME_STRONG_PASSWORD"

  PauseUpdatesYears = 10

  ChipsetDriversDir = "C:\ClubSetup\payload\Chipset"
  NvidiaInstaller   = "C:\ClubSetup\payload\Nvidia\NVIDIA_581.80.exe"

  WingetImportJson  = "C:\ClubSetup\apps.json"

  DrovaMsi          = "C:\ClubSetup\payload\Drova\drovaWindowsMerchantInstaller.msi"
  DrovaReg          = "C:\ClubSetup\payload\Drova\Drova.reg"

  VddXmlSource      = "C:\ClubSetup\vdd_settings.xml"
  VddXmlTarget      = "C:\VirtualDisplayDriver\vdd_settings.xml"

  TasksDir          = "C:\ClubSetup\tasks"
  LogsRoot          = "C:\ClubSetup\logs"

  CaptureMode       = $true
}
