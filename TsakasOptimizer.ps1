#requires -Version 5.1
<#
  TsakasOptimizer.ps1 - scans running processes + auto-start services, flags the ones
  commonly safe to close or switch to Manual, and asks before touching anything.
  Service changes are logged so -Undo can put them back.
  #>
[CmdletBinding()]
param([switch]$Console, [switch]$Report, [switch]$Undo, [switch]$SelfTest)

# PowerShell always gets a console and is DPI-unaware. The GUI wants neither: a
# hidden console whichever way the script was started, and real pixels instead of
# a window Windows stretches (and blurs) on a 125% or 150% display.
if (-not ($Console -or $Report -or $Undo -or $SelfTest)) {
  try {
    Add-Type -Name Startup -Namespace Tsakas -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
'@
    $wnd = [Tsakas.Startup]::GetConsoleWindow()
    if ($wnd -ne [IntPtr]::Zero) { [void][Tsakas.Startup]::ShowWindow($wnd, 0) }   # SW_HIDE
    # system-DPI aware, not per-monitor: WinForms cannot re-lay-out on a monitor
    # change without a manifest, and a stretched second monitor beats a broken one
    [void][Tsakas.Startup]::SetProcessDPIAware()
  } catch { }
}

$Version = '1.8.1'
$Repo    = 'TsakasOptimizations/TsakasOptimizer'
$Branch  = 'main'
$RawUrl  = "https://raw.githubusercontent.com/$Repo/$Branch/TsakasOptimizer.ps1"

$Root = if ($PSScriptRoot) { $PSScriptRoot } else { Join-Path $env:LOCALAPPDATA 'TsakasOptimizer' }
$UndoFile = Join-Path $Root 'optimizer-undo.json'

# --- updates -----------------------------------------------------------------
# The published script is the manifest: read its $Version line.
function Get-OnlineRelease {
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $text = (Invoke-WebRequest -Uri $RawUrl -UseBasicParsing -TimeoutSec 8).Content
    if ($text -match "(?m)^\s*\`$Version\s*=\s*'([\d.]+)'") {
      return [pscustomobject]@{ Version = $Matches[1]; Text = $text }
    }
  } catch { }
  return $null
}

function Install-Update([string]$Text) {
  if ($Text.Length -lt 5000 -or $Text -notmatch 'function Show-Gui') { throw 'the download looks incomplete' }
  Copy-Item $PSCommandPath "$PSCommandPath.bak" -Force
  Set-Content -Path $PSCommandPath -Value $Text -Encoding UTF8
  Update-SideFiles
}

# Everything that ships beside the script - so an in-app update is as complete
# as a fresh install. Failures here never fail the update itself.
function Update-SideFiles {
  if (-not $PSCommandPath) { return }
  $dir  = Split-Path $PSCommandPath
  $icon = Join-Path $dir 'icon.ico'
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/$Repo/$Branch/icon.ico" `
      -UseBasicParsing -TimeoutSec 20 -OutFile $icon
  } catch { }

  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  foreach ($lnk in @((Join-Path ([Environment]::GetFolderPath('Programs')) 'TsakasOptimizer.lnk'),
                     (Join-Path ([Environment]::GetFolderPath('Desktop'))  'TsakasOptimizer.lnk'))) {
    if (-not (Test-Path $lnk)) { continue }
    try {
      $shell = New-Object -ComObject WScript.Shell
      $s = $shell.CreateShortcut($lnk)
      # only touch shortcuts that already point at this copy
      if ($s.Arguments -notlike "*$PSCommandPath*") { continue }
      $s.TargetPath       = $ps
      $s.WorkingDirectory = $dir
      if (Test-Path $icon) { $s.IconLocation = $icon }
      $s.Save()
    } catch { }
  }
}

# --- app icon ----------------------------------------------------------------
# Carried in the script so the window is branded even when run straight from the
# web, where there is no icon file on disk. 16/32/48 only; the full icon.ico in
# the repo is what the installer puts on the shortcut.
$IconB64 = @(
  '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'
) -join ''

# The embedded .ico stores each size as a PNG. Icon.ToBitmap() cannot decode
# those, so this pulls the PNG bytes for one size straight out of the directory.
function Get-AppIconBitmap([int]$Size) {
  try {
    $bytes = [Convert]::FromBase64String($IconB64)
    $count = [BitConverter]::ToUInt16($bytes, 4)
    for ($i = 0; $i -lt $count; $i++) {
      $entry = 6 + 16 * $i
      $w = [int]$bytes[$entry]; if ($w -eq 0) { $w = 256 }
      if ($w -ne $Size) { continue }
      $len = [BitConverter]::ToInt32($bytes, $entry + 8)
      $off = [BitConverter]::ToInt32($bytes, $entry + 12)
      $png = New-Object byte[] $len
      [Array]::Copy($bytes, $off, $png, 0, $len)
      return [Drawing.Image]::FromStream((New-Object IO.MemoryStream(,$png)))
    }
  } catch { }
  return $null
}

function Get-AppIcon {
  try {
    $bytes = [Convert]::FromBase64String($IconB64)
    $stream = New-Object IO.MemoryStream(,$bytes)
    return New-Object Drawing.Icon($stream)
  } catch { return $null }
}

# --- never touch -------------------------------------------------------------
$Protected = @(
  'System','Idle','Registry','Memory Compression','smss','csrss','wininit','winlogon','services','lsass',
  'svchost','fontdrvhost','dwm','explorer','sihost','taskhostw','ctfmon','RuntimeBroker','SearchHost',
  'SearchIndexer','ShellExperienceHost','StartMenuExperienceHost','dllhost','conhost','WmiPrvSE','audiodg',
  'MsMpEng','NisSrv','SecurityHealth*','LsaIso','WUDFHost','powershell*','pwsh','WindowsTerminal',
  'Code','wsl*','vmmem*','nvcontainer','NVDisplay.Container*','TrustedInstaller','msedgewebview2'
)
$ProtectedServices = @(
  'WinDefend','wscsvc','SecurityHealthService','mpssvc','BFE','Dhcp','Dnscache','LanmanWorkstation',
  'LanmanServer','RpcSs','RpcEptMapper','DcomLaunch','Power','ProfSvc','Schedule','EventLog','CryptSvc',
  'BrokerInfrastructure','SystemEventsBroker','UserManager','Themes','Audiosrv','AudioEndpointBuilder',
  'nsi','NlaSvc','WlanSvc','netprofm','wuauserv','StateRepository','TimeBrokerSvc','gpsvc','SamSs',
  'EventSystem','SENS','ShellHWDetection','Winmgmt','PlugPlay','DeviceInstall','CoreMessagingRegistrar'
)

# --- possible to close/manual ------------------------------------------------------
# A = Kill (close it now) | Manual (service start type -> Manual, then stop)
$Catalog = @(
  @{M='AnyDesk*';             W='Remote desktop. Only needed while someone connects.';        A='Manual'}
  @{M='TeamViewer*';          W='Remote desktop. Only needed while someone connects.';        A='Manual'}
  @{M='RustDesk*';            W='Remote desktop. Only needed while someone connects.';        A='Manual'}
  @{M='*Steam Client Service*';W='Steam helper. Steam re-starts it when you launch Steam.';   A='Manual'}
  @{M='steam';                W='Game launcher sitting in the background.';                   A='Kill'}
  @{M='steamwebhelper';       W='Steam browser processes, usually the biggest RAM user.';     A='Kill'}
  @{M='EpicGamesLauncher';    W='Game launcher sitting in the background.';                   A='Kill'}
  @{M='EpicWebHelper';        W='Epic launcher helper.';                                      A='Kill'}
  @{M='*Epic Online Services*';W='Only needed while an Epic game is running.';                A='Manual'}
  @{M='Battle.net*';          W='Game launcher sitting in the background.';                   A='Kill'}
  @{M='GalaxyClient*';        W='GOG launcher sitting in the background.';                    A='Kill'}
  @{M='UbisoftConnect*';      W='Game launcher sitting in the background.';                   A='Kill'}
  @{M='upc';                  W='Ubisoft Connect.';                                           A='Kill'}
  @{M='EADesktop';            W='EA launcher sitting in the background.';                     A='Kill'}
  @{M='EABackgroundService';  W='EA background service.';                                     A='Manual'}
  @{M='RiotClient*';          W='Riot launcher sitting in the background.';                   A='Kill'}
  @{M='*Vanguard*';           W='Valorant anti-cheat. Valorant re-enables it when you play.'; A='Manual'}
  @{M='vgc';                  W='Valorant anti-cheat service.';                               A='Manual'}
  @{M='Discord';              W='Chat app. Close if you are not chatting.';                   A='Kill'}
  @{M='Slack';                W='Chat app. Close if you are not working.';                    A='Kill'}
  @{M='Teams';                W='Chat app, heavy. Close if not in a meeting.';                A='Kill'}
  @{M='ms-teams';             W='Chat app, heavy. Close if not in a meeting.';                A='Kill'}
  @{M='Spotify';              W='Music player. Close if not listening.';                      A='Kill'}
  @{M='WhatsApp';             W='Chat app.';                                                  A='Kill'}
  @{M='Telegram';             W='Chat app.';                                                  A='Kill'}
  @{M='Zoom*';                W='Only needed during calls.';                                  A='Kill'}
  @{M='OneDrive';             W='Cloud sync. Close it if you are not syncing right now.';     A='Kill'}
  @{M='Dropbox*';             W='Cloud sync running in the background.';                      A='Kill'}
  @{M='GoogleDriveFS';        W='Cloud sync running in the background.';                      A='Kill'}
  @{M='*Adobe*Update*';       W='Adobe updater. Manual is plenty.';                           A='Manual'}
  @{M='AGSService';           W='Adobe Genuine check. Apps run fine without it.';             A='Manual'}
  @{M='AGMService';           W='Adobe Genuine check. Apps run fine without it.';             A='Manual'}
  @{M='AdobeIPCBroker';       W='Creative Cloud background helper.';                          A='Kill'}
  @{M='Creative Cloud*';      W='Creative Cloud desktop app.';                                A='Kill'}
  @{M='CCXProcess';           W='Creative Cloud extras.';                                     A='Kill'}
  @{M='CoreSync';             W='Creative Cloud sync.';                                       A='Kill'}
  @{M='*Google Update*';      W='Chrome updater. Manual still updates while Chrome runs.';    A='Manual'}
  @{M='gupdate*';             W='Chrome updater service.';                                    A='Manual'}
  @{M='*edgeupdate*';         W='Edge updater service.';                                      A='Manual'}
  @{M='*brave*update*';       W='Brave updater service.';                                     A='Manual'}
  @{M='MozillaMaintenance';   W='Firefox updater service.';                                   A='Manual'}
  @{M='jusched';              W='Java updater.';                                              A='Kill'}
  @{M='*Java Update*';        W='Java updater service.';                                      A='Manual'}
  @{M='GoogleCrashHandler*';  W='Crash reporter.';                                            A='Kill'}
  @{M='*NVIDIA Telemetry*';   W='Telemetry only. No effect on games.';                        A='Manual'}
  @{M='NvTelemetryContainer'; W='Telemetry only. No effect on games.';                        A='Manual'}
  @{M='NVIDIA Share';         W='ShadowPlay overlay. Only needed if you record or stream.';   A='Kill'}
  @{M='NVIDIA Web Helper*';   W='GeForce Experience helper.';                                 A='Kill'}
  @{M='AppleMobileDeviceService';W='Only needed when an iPhone is plugged in.';               A='Manual'}
  @{M='Bonjour*';             W='Apple network discovery. Rarely needed.';                    A='Manual'}
  @{M='iTunesHelper';         W='Only needed when an Apple device is plugged in.';            A='Kill'}
  @{M='iCloud*';              W='Apple sync helper.';                                         A='Kill'}
  @{M='Razer*';               W='Peripheral software. Your settings stay on the device.';     A='Manual'}
  @{M='*Logitech*';           W='Peripheral software. Your settings stay on the device.';     A='Manual'}
  @{M='LGHUB*';               W='Logitech G HUB background app.';                             A='Kill'}
  @{M='*Corsair*';            W='iCUE peripheral software.';                                  A='Manual'}
  @{M='*Armoury*';            W='ASUS Armoury Crate. Known resource hog.';                    A='Manual'}
  @{M='*ASUS*';               W='ASUS bundled background service.';                           A='Manual'}
  @{M='*SteelSeries*';        W='Peripheral software.';                                       A='Manual'}
  @{M='MSIAfterburner';       W='Only needed while tuning or monitoring the GPU.';            A='Kill'}
  @{M='RTSS';                 W='RivaTuner. Only for the FPS overlay.';                       A='Kill'}
  @{M='DiagTrack';            W='Windows telemetry. Safe on Manual.';                         A='Manual'}
  @{M='dmwappushservice';     W='Telemetry transport. Safe on Manual.';                       A='Manual'}
  @{M='MapsBroker';           W='Offline maps. Not needed unless you use the Maps app.';      A='Manual'}
  @{M='RetailDemo';           W='Store demo mode. Never needed at home.';                     A='Manual'}
  @{M='Fax';                  W='Fax. Almost certainly not needed.';                          A='Manual'}
  @{M='RemoteRegistry';       W='Remote registry access. Better left off.';                   A='Manual'}
  @{M='PrintNotify';          W='Printer popups. Fine on Manual if you rarely print.';        A='Manual'}
  @{M='Spooler';              W='Print spooler. Only set Manual if you have no printer.';     A='Manual'}
  @{M='WSearch';              W='Search index. Manual means slower Start-menu search.';       A='Manual'}
  @{M='Xbl*';                 W='Xbox service. Games re-start it on demand.';                 A='Manual'}
  @{M='XboxNetApiSvc';        W='Xbox networking. Games re-start it on demand.';              A='Manual'}
  @{M='XboxGipSvc';           W='Xbox controller service. Manual if you have no Xbox pad.';   A='Manual'}
  @{M='GameBar*';             W='Xbox Game Bar helper.';                                      A='Kill'}
  @{M='Skype*';               W='Chat app.';                                                  A='Kill'}
  @{M='Cortana';              W='Assistant, rarely used.';                                    A='Kill'}
  @{M='*Dell*Update*';        W='OEM updater. Manual is plenty.';                             A='Manual'}
  @{M='*Lenovo*';             W='Lenovo bundled background service.';                         A='Manual'}
  @{M='*Acer*';               W='Acer bundled background service.';                           A='Manual'}
  @{M='CCleaner*';            W='Only needed when you actually run a clean.';                 A='Manual'}
  @{M='*Wondershare*';        W='Bundled updater/helper.';                                    A='Manual'}
  @{M='qbittorrent*';         W='Torrent client. Uses disk and network constantly.';          A='Kill'}
  @{M='utorrent*';            W='Torrent client. Uses disk and network constantly.';          A='Kill'}
) | ForEach-Object { [pscustomobject]$_ }

# --- scoring unknown stuff ---------------------------------------------------
# Anything the catalog misses is scored on behaviour: autostart, window, name, size.
$BloatWords = 'updat|upgrad|telemetr|helper|agent|crash|report|tray|notif|daemon|launcher|overlay|assist|booster|cleaner|doctor|toolbar|companion|widget|analytic'

# never scored - too risky to disable on a heuristic
$NeverGuess = 'defender|antivir|antimalware|security|firewall|vpn|backup|bitlocker|encrypt|audio|realtek|nvidia|amd |intel\(r\)|driver|bluetooth|network|storage|raid|nvme|hyper-v|vmware|virtualbox|wsl'

function Get-AutoStartNames {
  # Get-ScheduledTask costs ~0.7s; startup entries cannot change mid-run, so read once.
  if ($script:AutoNames) { return $script:AutoNames }
  $set = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
  $add = { param($text) foreach ($m in [regex]::Matches([string]$text, '([^\\/":\s]+)\.exe')) { [void]$set.Add($m.Groups[1].Value) } }

  foreach ($k in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
                   'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
                   'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run')) {
    if (-not (Test-Path $k)) { continue }
    $item = Get-Item $k
    foreach ($n in $item.GetValueNames()) { & $add $item.GetValue($n) }
  }
  foreach ($d in @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup'))) {
    foreach ($f in (Get-ChildItem $d -File -ErrorAction SilentlyContinue)) { [void]$set.Add($f.BaseName) }
  }
  # tasks that run at logon or boot
  foreach ($t in (Get-ScheduledTask -ErrorAction SilentlyContinue)) {
    $trig = $t.Triggers.CimClass.CimClassName
    if ($trig -notcontains 'MSFT_TaskLogonTrigger' -and $trig -notcontains 'MSFT_TaskBootTrigger') { continue }
    [void]$set.Add(($t.TaskName -replace '\s.*$', ''))
    foreach ($a in $t.Actions) { & $add $a.Execute }
  }
  $script:AutoNames = $set
  $set
}

function Test-AutoStarts([string]$Name, $AutoNames) {
  if (-not $AutoNames -or -not $Name) { return $false }
  if ($AutoNames.Contains($Name)) { return $true }
  # "Overwolf" running, "OverwolfLauncher" in the Run key - same app
  foreach ($a in $AutoNames) {
    if ($a.Length -ge 4 -and $Name.Length -ge 4 -and
        ($a.StartsWith($Name, 'OrdinalIgnoreCase') -or $Name.StartsWith($a, 'OrdinalIgnoreCase'))) { return $true }
  }
  return $false
}

# $Info: Name, HasWindow, RamMB, Company, AutoStart, BootMinutes
function Get-ProcessGuess($Info) {
  $score = 0; $why = New-Object System.Collections.ArrayList
  if ("$($Info.Name) $($Info.Company)" -match $NeverGuess) {
    return [pscustomobject]@{ Score = 0; Reasons = @() }
  }
  if ($Info.Name -match $BloatWords) {
    $score += 3; [void]$why.Add('name looks like a helper/updater rather than the app itself')
  }
  if ($Info.AutoStart) {
    $score += 3; [void]$why.Add('starts itself with Windows')
  } elseif ($Info.BootMinutes -ne $null -and $Info.BootMinutes -le 2) {
    $score += 1; [void]$why.Add('was already running seconds after boot')
  }
  if ($Info.HasWindow) {
    $score -= 4; [void]$why.Add('it has a window open, so you are probably using it')
  } else {
    $score += 2; [void]$why.Add('no window - it only runs in the background')
  }
  if ($Info.RamMB -ge 100) {
    $score += 1; [void]$why.Add("using $($Info.RamMB) MB")
  }
  [pscustomobject]@{ Score = $score; Reasons = $why }
}

# $Info: Name, DisplayName, PathName, State
function Get-ServiceGuess($Info) {
  $score = 0; $why = New-Object System.Collections.ArrayList
  $text = "$($Info.Name) $($Info.DisplayName)"
  if ($text -match $NeverGuess) { return [pscustomobject]@{ Score = 0; Reasons = @() } }
  if ($Info.PathName -like "$env:SystemRoot\*") { return [pscustomobject]@{ Score = 0; Reasons = @() } }

  $score += 2; [void]$why.Add('third-party service set to start with Windows')
  if ($text -match $BloatWords) {
    $score += 3; [void]$why.Add('name suggests an updater/helper, not the program you actually run')
  }
  if ($Info.State -eq 'Stopped') {
    $score += 1; [void]$why.Add('set to Automatic but not even running right now')
  }
  [pscustomobject]@{ Score = $score; Reasons = $why }
}

# --- helpers -----------------------------------------------------------------
function Test-Match([string]$Name, [string[]]$Patterns) {
  if (-not $Name) { return $false }
  foreach ($p in $Patterns) { if ($Name -like $p) { return $true } }
  return $false
}

function Get-Suggestion([string]$Name, [string]$Display) {
  foreach ($e in $Catalog) {
    if ((Test-Match $Name @($e.M)) -or (Test-Match $Display @($e.M))) { return $e }
  }
  return $null
}

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Flattens whatever shape the file is in: a bare object, a proper array, or the
# nested { value = (...); Count = n } wrappers older builds wrote.
function Expand-UndoEntries($Node, $Sink) {
  if ($null -eq $Node) { return }
  if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string]) {
    foreach ($item in $Node) { Expand-UndoEntries $item $Sink }
    return
  }
  $names = @($Node.PSObject.Properties.Name)
  if ($names -contains 'Type') { [void]$Sink.Add($Node); return }
  if ($names -contains 'value') { Expand-UndoEntries $Node.value $Sink }
}

function Read-UndoLog([string]$Path = $UndoFile) {
  $entries = New-Object System.Collections.ArrayList
  if (-not (Test-Path $Path)) { return @() }
  $raw = (Get-Content $Path -Raw)
  if (-not $raw -or -not $raw.Trim()) { return @() }
  try { Expand-UndoEntries ($raw | ConvertFrom-Json) $entries } catch { }
  return @($entries)
}

function Add-UndoEntry($Entry, [string]$Path = $UndoFile) {
  $dir = Split-Path $Path
  if ($dir -and -not (Test-Path $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
  $log = New-Object System.Collections.ArrayList
  foreach ($e in (Read-UndoLog $Path)) { [void]$log.Add($e) }
  [void]$log.Add($Entry)
  # -InputObject, because piping an array here is what nested the log in the first place
  ConvertTo-Json -InputObject @($log) -Depth 5 | Out-File $Path -Encoding utf8
}

function Invoke-Undo {
  if (-not (Test-Path $UndoFile)) { Write-Host 'Nothing to undo.'; return }
  if (-not (Test-Admin)) { Write-Host 'Run as Administrator to restore services.' -ForegroundColor Yellow; return }
  $failed = New-Object System.Collections.ArrayList
  foreach ($e in (Read-UndoLog)) {
    try {
      switch ($e.Type) {
        'AppStartup' {
          New-ItemProperty -Path $e.Key -Name $e.Name -Value $e.Data -PropertyType String -Force | Out-Null
        }
        'NetProperty' {
          Set-NetAdapterAdvancedProperty -Name $e.Adapter -DisplayName $e.Name -DisplayValue $e.Previous -ErrorAction Stop
        }
        'TcpipReg' {
          New-ItemProperty -Path $TcpipKey -Name $e.Name -Value ([int]$e.Previous) -PropertyType DWord -Force | Out-Null
        }
        'NetPower' {
          $pm = Get-NetAdapterPowerManagement -Name $e.Adapter -ErrorAction Stop
          $pm.AllowComputerToTurnOffDevice = $e.Previous
          Set-NetAdapterPowerManagement -InputObject $pm -ErrorAction Stop
        }
        default { Set-Service -Name $e.Name -StartupType $e.Previous }
      }
      Write-Host ("restored {0} -> {1}" -f $e.Name, $e.Previous) -ForegroundColor Green
    } catch {
      Write-Host ("could not restore {0}: {1}" -f $e.Name, $_.Exception.Message) -ForegroundColor Red
      [void]$failed.Add($e)
    }
  }
  # keep whatever could not be restored, so a second attempt is still possible
  if ($failed.Count -eq 0) { Remove-Item $UndoFile }
  else { ConvertTo-Json -InputObject @($failed) -Depth 5 | Out-File $UndoFile -Encoding utf8 }
}

# --- scan --------------------------------------------------------------------
function Get-Findings {
  $found = New-Object System.Collections.ArrayList
  $autoNames = Get-AutoStartNames
  $boot = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).LastBootUpTime

  foreach ($g in (Get-Process | Group-Object ProcessName)) {
    if (Test-Match $g.Name $Protected) { continue }
    $ram = [math]::Round((($g.Group | Measure-Object WorkingSet64 -Sum).Sum) / 1MB, 1)
    $s = Get-Suggestion $g.Name $null

    if ($s) {
      [void]$found.Add([pscustomobject]@{
        Type = 'Process'; Name = $g.Name; Label = $g.Name; RamMB = $ram; Count = $g.Count
        Why = $s.W; Action = 'Kill'; Extra = ''; Confidence = 'Known'
      })
      continue
    }

    # not in the catalog - score it
    $first = $g.Group[0]
    $path = try { $first.Path } catch { '' }
    if (-not $path) { continue }                       # cannot inspect it, so do not guess
    if ($path -like "$env:SystemRoot\*") { continue }  # part of Windows
    $started = try { $first.StartTime } catch { $null }
    $company = try { $first.Company } catch { '' }
    $info = [pscustomobject]@{
      Name        = $g.Name
      HasWindow   = (($g.Group | Where-Object { $_.MainWindowHandle -ne 0 }).Count -gt 0)
      RamMB       = $ram
      Company     = $company
      AutoStart   = (Test-AutoStarts $g.Name $autoNames)
      BootMinutes = $(if ($started -and $boot) { ($started - $boot).TotalMinutes } else { $null })
    }
    $guess = Get-ProcessGuess $info
    if ($guess.Score -lt 5) { continue }
    [void]$found.Add([pscustomobject]@{
      Type = 'Process'; Name = $g.Name; Label = $g.Name; RamMB = $ram; Count = $g.Count
      Why = ("Flagged because: " + ($guess.Reasons -join '; ') + ".")
      Action = 'Kill'; Extra = ''; Confidence = 'Guess'
    })
  }

  foreach ($svc in (Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)) {
    if ($svc.StartMode -ne 'Auto') { continue }
    if (Test-Match $svc.Name $ProtectedServices) { continue }
    $ram = 0
    if ($svc.ProcessId -gt 0) {
      $p = Get-Process -Id $svc.ProcessId -ErrorAction SilentlyContinue
      if ($p) { $ram = [math]::Round($p.WorkingSet64 / 1MB, 1) }
    }
    $s = Get-Suggestion $svc.Name $svc.DisplayName

    if ($s) {
      [void]$found.Add([pscustomobject]@{
        Type = 'Service'; Name = $svc.Name; Label = $svc.DisplayName; RamMB = $ram; Count = 1
        Why = $s.W; Action = 'Manual'; Extra = $svc.State; Confidence = 'Known'
      })
      continue
    }

    $exe = $svc.PathName -replace '^"([^"]+)".*', '$1' -replace '^(\S+\.exe).*', '$1'
    $guess = Get-ServiceGuess ([pscustomobject]@{
      Name = $svc.Name; DisplayName = $svc.DisplayName; PathName = $exe; State = $svc.State })
    if ($guess.Score -lt 4) { continue }
    [void]$found.Add([pscustomobject]@{
      Type = 'Service'; Name = $svc.Name; Label = $svc.DisplayName; RamMB = $ram; Count = 1
      Why = ("Flagged because: " + ($guess.Reasons -join '; ') + ". Manual is reversible - if something breaks, press Undo.")
      Action = 'Manual'; Extra = $svc.State; Confidence = 'Guess'
    })
  }

  $found | Sort-Object -Property @{E = { $_.Confidence -eq 'Guess' }}, @{E = 'RamMB'; D = $true}
}

# --- act ---------------------------------------------------------------------
function Invoke-Finding($f) {
  if ($f.Action -eq 'Kill') {
    Stop-Process -Name $f.Name -Force -ErrorAction Stop
    Write-Host ("      closed {0} (freed about {1} MB)" -f $f.Name, $f.RamMB) -ForegroundColor Green
    return $f.RamMB
  }
  if (-not (Test-Admin)) {
    Write-Host '      needs Administrator - skipped.' -ForegroundColor Yellow
    return 0
  }
  $svc = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $f.Name)
  Add-UndoEntry ([pscustomobject]@{
    Type = 'Service'; Name = $f.Name; Previous = $svc.StartMode; When = (Get-Date).ToString('s')
  })
  Set-Service -Name $f.Name -StartupType Manual -ErrorAction Stop
  if ($svc.State -eq 'Running') { Stop-Service -Name $f.Name -Force -ErrorAction SilentlyContinue }
  Write-Host ("      {0} set to Manual (undo with -Undo)" -f $f.Name) -ForegroundColor Green
  return $f.RamMB
}

# --- memory ------------------------------------------------------------------
# Slot naming is board-specific (DIMM 0/1, DIMM_A1, ChannelA-DIMM1...). The raw
# locator is always shown so it can be checked against the motherboard manual.
# Desktop AM5 is Ryzen 7000/8000/9000 with a desktop suffix or none. Mobile parts
# (7735HS, 7945HX) carry the same number ranges but are soldered laptop chips, and
# the desktop memory advice does not apply to them.
function Test-Am5([string]$Cpu) {
  return ($Cpu -match '(?i)Ryzen\s+\d\s+[789]\d{3}(X3D|XT|X|GE|G|F)?(\s|$)')
}

function Get-DimmChannel([string]$Bank, [string]$Locator) {
  if ($Bank -match '(?i)channel\s*([A-D])')    { return $Matches[1].ToUpper() }
  if ($Locator -match '(?i)([A-D])\s*\d')      { return $Matches[1].ToUpper() }
  if ($Bank) { return $Bank }
  return '?'
}

function Get-DimmSlotIndex([string]$Locator) {
  if ($Locator -match '(?i)[A-D]\s*(\d)') { return [int]$Matches[1] }        # A1 / B2 -> 1-based
  if ($Locator -match '(\d+)\s*$')        { return [int]$Matches[1] + 1 }    # DIMM 0 / DIMM 1 -> 0-based
  return 0                                                                    # unknown
}

# Vendors encode the rated timings in the part number:
#   G.SKILL DDR5 F5-6000J3038F16G -> J3038 = CL30, tRCD/tRP 38
#   G.SKILL DDR4 F4-3600C16D-32GTZN, Corsair CMK32GX5M2B6000C36, Kingston KF560C36 -> C36
function Get-PartTimings([string]$Part) {
  $cl = $null; $trcd = $null; $trp = $null
  if ($Part -match 'J(\d{2})(\d{2})(\d{2})?') {
    $cl = [int]$Matches[1]; $trcd = [int]$Matches[2]
    $trp = if ($Matches[3]) { [int]$Matches[3] } else { $trcd }
  } elseif ($Part -match 'C(\d{2})') {
    $cl = [int]$Matches[1]
  }
  [pscustomobject]@{ CL = $cl; tRCD = $trcd; tRP = $trp }
}

# G.SKILL F5-6000J..., Corsair CMK32GX5M2B6000C36, Kingston KHX3200C16 - the
# rated transfer rate is in the part number, which is the only rating available
# when the board reports Speed as whatever the memory is currently running at.
function Get-PartSpeed([string]$Part) {
  foreach ($m in [regex]::Matches(("$Part"), '(\d{4,5})')) {
    $v = [int]$m.Groups[1].Value
    if ($v -ge 1600 -and $v -le 12000) { return $v }
  }
  return 0
}

function Get-Dimms {
  foreach ($m in (Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)) {
    $type = switch ($m.SMBIOSMemoryType) {
      34 { 'DDR5' } 26 { 'DDR4' } 24 { 'DDR3' } 21 { 'DDR2' } 20 { 'DDR' } default { "type $($m.SMBIOSMemoryType)" }
    }
    $t = Get-PartTimings $m.PartNumber
    $cl = $t.CL; $trcd = $t.tRCD; $trp = $t.tRP
    [pscustomobject]@{
      Channel = Get-DimmChannel $m.BankLabel $m.DeviceLocator
      Slot    = Get-DimmSlotIndex $m.DeviceLocator
      Locator = ("{0} / {1}" -f $m.BankLabel, $m.DeviceLocator).Trim(' /')
      GB      = [math]::Round($m.Capacity / 1GB, 0)
      Type    = $type
      Rated   = [int]$m.Speed
      Running = [int]$m.ConfiguredClockSpeed
      Vendor  = ($m.Manufacturer + '').Trim()
      Part    = ($m.PartNumber + '').Trim()
      CL      = $cl
      tRCD    = $trcd
      tRP     = $trp
    }
  }
}

function Get-MemoryNotes([object[]]$Dimms, [int]$Slots, [string]$Cpu) {
  $n = New-Object System.Collections.ArrayList
  if (-not $Dimms -or $Dimms.Count -eq 0) {
    [void]$n.Add('Could not read memory information from Windows.')
    return $n
  }

  $am5  = Test-Am5 $Cpu
  $ddr5 = $Dimms[0].Type -eq 'DDR5'
  $spdRated  = ($Dimms | Measure-Object Rated -Maximum).Maximum
  $run       = ($Dimms | Measure-Object Running -Minimum).Minimum
  $partRated = 0
  foreach ($d in $Dimms) { $partRated = [Math]::Max($partRated, (Get-PartSpeed $d.Part)) }
  $rated = [Math]::Max($spdRated, $partRated)

  # 1. EXPO / XMP
  if ($run -gt 0 -and $rated -gt 0 -and $run -lt ($rated - 50)) {
    [void]$n.Add(("[!] EXPO/XMP is OFF: rated {0}, running {1} MT/s ({2}%). Fix in BIOS: EXPO (AMD) or XMP (Intel), Profile 1, save, reboot." -f $rated, $run, [math]::Round(100 * $run / $rated)))
  } elseif ($ddr5 -and $run -le 5600 -and $rated -le 5600) {
    [void]$n.Add(("[i] Running {0} MT/s, the JEDEC default. If the box says 6000+, the profile is not loading - check BIOS." -f $run))
  } else {
    [void]$n.Add(("[ok] EXPO/XMP on: rated {0}, running {1} MT/s." -f $rated, $run))
  }
  if ($partRated -gt ($spdRated + 50)) {
    [void]$n.Add(("    Rating read from the part number ({0}); this board only reports the running speed ({1})." -f $partRated, $spdRated))
  }

  # 2. slots
  $channels = @($Dimms | Group-Object Channel)
  if ($Dimms.Count -eq 2 -and $Slots -ge 4) {
    if ($channels.Count -lt 2) {
      [void]$n.Add(("[!] Both sticks in channel {0}: single channel, half the bandwidth. Move one to slot 2 or 4." -f $channels[0].Name))
    } elseif (($Dimms | Where-Object { $_.Slot -eq 2 }).Count -eq 2) {
      [void]$n.Add('[ok] Dual channel, both sticks in A2/B2. Correct placement.')
    } elseif (($Dimms | Where-Object { $_.Slot -eq 1 }).Count -eq 2) {
      [void]$n.Add('[!] Sticks are in A1/B1. Move them to slots 2 and 4 (A2/B2) - A1/B1 often will not hold EXPO.')
    } else {
      [void]$n.Add(('[i] Slot layout unclear (' + (($Dimms | ForEach-Object { $_.Locator }) -join ' | ') + '). Two sticks belong in slots 2 and 4.'))
    }
  } elseif ($Dimms.Count -eq 2 -and $Slots -eq 2) {
    # two-slot boards (ITX, laptops) have no wrong pair to move to
    $dual = $(if ($channels.Count -ge 2) { '[ok] Two-slot board, both filled: dual channel.' } else { '[!] Two-slot board but both sticks report one channel - check the manual.' })
    [void]$n.Add($dual)
  } elseif ($Dimms.Count -eq 1) {
    [void]$n.Add('[!] One stick: single channel. A second identical stick is the cheapest big gain.')
  } elseif ($Dimms.Count -ge 4 -and $ddr5) {
    [void]$n.Add('[i] Four DDR5 sticks: 5600 or lower is normal here, not a fault.')
  }

  # 3. mixed kit
  if (($Dimms | Select-Object -ExpandProperty Part -Unique).Count -gt 1 -or
      ($Dimms | Select-Object -ExpandProperty GB   -Unique).Count -gt 1) {
    [void]$n.Add('[!] Sticks are not identical. Mixed kits often miss their rated profile - first suspect if EXPO is unstable.')
  }

  # 4. platform target
  [void]$n.Add('')
  [void]$n.Add('--- PROCEED WITH CAUTION - BIOS tuning below. Wrong values mean no boot (clear CMOS to recover). One change at a time. ---')
  if ($am5 -and $ddr5) {
    [void]$n.Add('[i] AM5 target: DDR5-6000 CL30, FCLK 2000, 1:1. Past ~6400 it drops to 2:1 and gets slower.')
  } elseif ($ddr5) {
    [void]$n.Add('[i] Intel DDR5 target: 6400-7200 if the board and kit allow it.')
  } else {
    [void]$n.Add('[i] DDR4 target: 3600 CL16 on Ryzen (FCLK 1800, 1:1), 3600-4000 on Intel.')
  }

  # 5. timings
  $cl = ($Dimms | Where-Object { $_.CL } | Select-Object -First 1).CL
  if ($cl) {
    [void]$n.Add(("[i] Part number says CL{0}{1} at {2} MT/s (rated profile, not necessarily loaded)." -f
      $cl, $(if ($Dimms[0].tRCD) { "-$($Dimms[0].tRCD)-$($Dimms[0].tRP)" } else { '' }), $rated))
    if ($ddr5 -and $rated -ge 6000 -and $cl -ge 30) {
      [void]$n.Add('    Tightening, one at a time: CL 30->28, tRCD/tRP->36, tRAS->32, tRFC ~480ns. VDD/VDDQ 1.35-1.40V. Worth 1-3%.')
    } elseif ($ddr5) {
      [void]$n.Add('    Get the rated profile stable first. Tightening past it is worth 1-3%.')
    } else {
      [void]$n.Add('    DDR4: tCL, tRCD/tRP and tRFC matter most. B-die tightens far more than Hynix/Micron.')
    }
  }

  [void]$n.Add('')
  [void]$n.Add('Windows cannot read live timings - the values above are the SPD profile. Real ones: BIOS, ZenTimings (AM5) or CPU-Z SPD.')
  [void]$n.Add('Test any change for an hour with TestMem5 (anta777) or Karhu.')
  [void]$n.Add('')
  [void]$n.Add('Need advice specific to your rig? Discord: _tsakas_  or X: @TsakasIoannis')
  return $n
}

# --- motherboard and drivers -------------------------------------------------
function Get-BoardInfo {
  $bb   = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
  $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
  $cs   = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
  $date = $bios.ReleaseDate
  [pscustomobject]@{
    Vendor    = ($bb.Manufacturer, $cs.Manufacturer | Where-Object { $_ } | Select-Object -First 1)
    Model     = ($bb.Product, $cs.Model | Where-Object { $_ } | Select-Object -First 1)
    Bios      = $bios.SMBIOSBIOSVersion
    BiosDate  = $date
    AgeMonths = $(if ($date) { [math]::Round(((Get-Date) - $date).TotalDays / 30.4, 1) } else { $null })
    Cpu       = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Name
  }
}

function Get-BiosNotes($Board) {
  $n = New-Object System.Collections.ArrayList
  if (-not $Board.Bios) { [void]$n.Add('Could not read BIOS information.'); return $n }

  [void]$n.Add(("Board: {0} {1}" -f $Board.Vendor, $Board.Model))
  [void]$n.Add(("BIOS:  {0}, released {1:yyyy-MM-dd} ({2} months ago)" -f $Board.Bios, $Board.BiosDate, $Board.AgeMonths))
  [void]$n.Add('')

  $am5 = Test-Am5 $Board.Cpu
  if ($Board.AgeMonths -lt 6) {
    [void]$n.Add('[ok] Recent BIOS. Nothing to do unless you are chasing a specific bug.')
  } elseif ($Board.AgeMonths -lt 18) {
    [void]$n.Add('[i] A newer BIOS likely exists. Update only for a reason: memory instability, a new CPU, a fix in the changelog.')
  } else {
    [void]$n.Add('[!] BIOS is over 18 months old. Check the changelog on the support page.')
  }
  if ($am5) {
    [void]$n.Add('    AM5: BIOS updates carry AGESA fixes for memory training and EXPO. First thing to try with fussy RAM.')
  }
  [void]$n.Add('')
  [void]$n.Add('Windows cannot tell you the newest version - only the vendor page can. Use the button below and match your exact model.')
  [void]$n.Add('')
  [void]$n.Add('--- PROCEED WITH CAUTION - a failed flash can leave the board unbootable. Use the vendor tool, never flash an unstable PC, do not cut power. ---')
  return $n
}

# Per-device chipset drivers (PCI, SMBus, GPIO and friends) each carry their own
# small version number. What people mean by "chipset driver" is the installed
# package, which lives in the uninstall registry - the same place the Settings
# app reads it from.
function Get-ChipsetPackage {
  $keys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
  $hits = @(Get-ItemProperty $keys -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match '(?i)chipset' -and $_.DisplayVersion })
  if (-not $hits) { return $null }

  # the same package is often registered twice; prefer the readable name
  $named = @($hits | Where-Object { $_.DisplayName -notmatch '_' })
  $name = $(if ($named) { $named[0].DisplayName } else { $hits[0].DisplayName })
  $date = $null
  foreach ($h in $hits) {
    if ("$($h.InstallDate)" -match '^\d{8}$') { $date = [datetime]::ParseExact($h.InstallDate, 'yyyyMMdd', $null); break }
  }
  [pscustomobject]@{ Name = $name; Version = $hits[0].DisplayVersion; Publisher = $hits[0].Publisher; Date = $date }
}

# Only these classes matter here; the query is filtered server-side to keep it quick.
function Get-DriverInfo {
  $rows = New-Object System.Collections.ArrayList
  $all = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue -Filter `
    "DeviceClass='NET' OR DeviceClass='MEDIA' OR DeviceClass='SYSTEM' OR DeviceClass='DISPLAY'"

  # virtual and debug adapters are not drivers anyone updates
  $noise = 'Miniport|Kernel Debug|Virtual|Loopback|Teefer|TAP-|Wintun|Wi-Fi Direct|Microsoft Hyper-V'

  foreach ($g in @(
      @{ Cat = 'Chipset'; Rows = @($all | Where-Object { $_.DeviceClass -eq 'SYSTEM' -and $_.DriverProviderName -notlike 'Microsoft*' }) }
      @{ Cat = 'Network'; Rows = @($all | Where-Object { $_.DeviceClass -eq 'NET' -and $_.DeviceName -notmatch $noise -and $_.DriverProviderName -notlike 'Microsoft*' }) }
      @{ Cat = 'Audio';   Rows = @($all | Where-Object { $_.DeviceClass -eq 'MEDIA' -and $_.DeviceName -notmatch $noise }) }
      @{ Cat = 'Graphics';Rows = @($all | Where-Object { $_.DeviceClass -eq 'DISPLAY' }) })) {

    if ($g.Rows.Count -eq 0) {
      [void]$rows.Add([pscustomobject]@{
        Category = $g.Cat; Device = 'none found with a vendor driver'; Provider = 'Microsoft generic'
        Version = '-'; Date = $null; Note = 'Windows is using its own driver. The vendor one usually adds features and fixes.' })
      continue
    }
    # chipset ships as one package, so report the package, not one of its devices
    if ($g.Cat -eq 'Chipset') {
      $oldest = $g.Rows | Sort-Object DriverDate | Select-Object -First 1
      $pkg = Get-ChipsetPackage
      if ($pkg) {
        [void]$rows.Add([pscustomobject]@{
          Category = 'Chipset'; Device = ("{0} ({1} devices)" -f $pkg.Name, $g.Rows.Count)
          Provider = $pkg.Publisher; Version = $pkg.Version; Date = $pkg.Date
          Note = (Get-DriverNote $pkg.Publisher $pkg.Date) })
      } else {
        [void]$rows.Add([pscustomobject]@{
          Category = 'Chipset'; Device = ("{0} chipset, oldest of {1} device drivers" -f ($oldest.DriverProviderName -replace ',.*$', ''), $g.Rows.Count)
          Provider = $oldest.DriverProviderName; Version = $oldest.DriverVersion; Date = $oldest.DriverDate
          Note = (Get-DriverNote $oldest.DriverProviderName $oldest.DriverDate) })
      }
      continue
    }
    foreach ($d in $g.Rows) {
      $inf = $d.InfName
      $hwid = $(if ($d.HardWareID) { @($d.HardWareID)[0] } else { '' })
      $version = $(if ($g.Cat -eq 'Graphics') { Get-GpuVersion $d.DriverProviderName $d.DriverVersion } else { $d.DriverVersion })
      [void]$rows.Add([pscustomobject]@{
        Category = $g.Cat; Device = $d.DeviceName; Provider = $d.DriverProviderName
        Version = $version; Date = $d.DriverDate
        Note = (Get-DriverNote $d.DriverProviderName $d.DriverDate $inf $hwid) })
    }
  }
  $rows
}

# Windows keeps its own version for GPU drivers, and it is not the number the
# vendor publishes. NVIDIA's is the last five digits (32.0.16.1088 -> 610.88);
# Intel drops the two Windows components (32.0.101.6314 -> 101.6314). AMD's
# Adrenalin version is not derivable from it, so that one is left as it is.
function Get-GpuVersion([string]$Provider, [string]$Version) {
  if (-not $Version) { return $Version }
  if ($Provider -like 'NVIDIA*') {
    $d = ($Version -replace '\D', '')
    if ($d.Length -ge 5) {
      $last = $d.Substring($d.Length - 5)
      return ("{0}.{1}" -f $last.Substring(0, 3), $last.Substring(3, 2))
    }
  }
  if ($Provider -like 'Intel*') {
    $parts = $Version -split '\.'
    if ($parts.Count -eq 4) { return ("{0}.{1}" -f $parts[2], $parts[3]) }
  }
  return $Version
}

function Get-DriverNote([string]$Provider, $Date, [string]$Inf, [string]$HardwareId) {
  $notes = @()
  if ($Provider -like 'Microsoft*') {
    if ($Inf -match '(?i)^usbaudio') {
      # the USB Audio class driver is the normal one; vendors rarely ship another
      $notes += 'USB Audio class driver, which is the standard one for USB audio devices'
    } elseif ($Inf -match '(?i)^hdaudio' -and $HardwareId -match '(?i)VEN_10DE') {
      $notes += 'HDMI audio on the generic driver - NVIDIA ships one inside its display driver package'
    } elseif ($Inf -match '(?i)^hdaudio' -and $HardwareId -match '(?i)VEN_1002') {
      $notes += 'HDMI audio on the generic driver - AMD ships one inside its display driver package'
    } else {
      $notes += 'generic Windows driver - the vendor one usually adds features and fixes'
    }
  }
  # Microsoft stamps inbox drivers 21 June 2006, so their age means nothing
  $placeholder = $Date -and $Date.Year -eq 2006 -and $Date.Month -eq 6 -and $Date.Day -eq 21
  if ($Date -and -not $placeholder) {
    $years = ((Get-Date) - $Date).TotalDays / 365
    if ($years -gt 3)     { $notes += 'over 3 years old' }
    elseif ($years -gt 2) { $notes += 'over 2 years old' }
  }
  $notes -join '; '
}

# --- network adapters --------------------------------------------------------
# Link power saving buys a fraction of a watt and costs latency spikes and the
# occasional dropped link. Worth turning off on a desktop, pointless on a laptop
# running from battery.
$NetPowerProps = 'Energy.Efficient|Advanced EEE|Green Ethernet|Gigabit Lite|Power Saving|Selective Suspend|Ultra Low Power|Idle Power|Reduce Speed|Auto Disable|Energy Detect'

# Trade CPU time for latency. Microsoft's adapter tuning guide suggests interrupt
# moderation off for the lowest latency; checksum offload off helps on some
# adapter firmware and does nothing on others. Offered, never assumed.
# Large Send Offload and Receive Segment Coalescing only touch TCP, not the UDP
# games use, so they are left alone.
$NetLatencyProps = '^Interrupt Moderation$|Checksum Offload'

$TcpipKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'

function Get-NetGroup([string]$DisplayName) {
  if ($DisplayName -match $NetPowerProps)   { return 'Power saving' }
  if ($DisplayName -match $NetLatencyProps) { return 'Latency (optional)' }
  return $null
}

$NetWhy = @{
  'Energy-Efficient Ethernet' = 'Powers the link down between packets. Saves under a watt, and is a known cause of latency spikes and dropped links.'
  'Advanced EEE'              = 'Aggressive version of the same link power saving. Same trade, worse.'
  'Green Ethernet'            = 'Cuts transmit power based on cable length. Can cause renegotiation on marginal cables.'
  'Gigabit Lite'              = 'Runs the link in a lower-power mode. Can drop you to a slower speed.'
  'Power Saving Mode'         = 'Vendor power saving for the adapter. Trades latency for a trivial amount of power.'
  'Selective Suspend'         = 'Lets Windows suspend the adapter when idle. It wakes late, so the first packet after a pause is slow.'
  'Interrupt Moderation'      = 'Groups several packets into one interrupt to save CPU, which adds a few microseconds before each batch is handled. Microsoft suggests turning it off for the lowest latency; the cost is more CPU time. Optional - test your games with it off before keeping it.'
}
$NetChecksumWhy = 'Lets the network card check packets instead of the CPU. Off moves that work back to the CPU. Some adapter firmware handles offloads badly, so this can help, but on a good driver it changes nothing. Optional - test before keeping it.'

# Returns the value to set it to, or $null when the property is not a simple
# on/off switch or is already off.
function Get-NetOffValue([string]$DisplayName, [string]$Current, $ValidValues) {
  if (-not (Get-NetGroup $DisplayName)) { return $null }
  $off = @($ValidValues) | Where-Object { $_ -match '^\s*(Disabled|Off)\s*$' } | Select-Object -First 1
  if (-not $off) { return $null }                          # e.g. "EEE Max Support Speed" is a speed list
  if ($Current -match '^\s*(Disabled|Off)\s*$') { return $null }
  return $off
}

function Get-NetFindings {
  $rows = New-Object System.Collections.ArrayList
  foreach ($a in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Not Present' })) {
    foreach ($p in @(Get-NetAdapterAdvancedProperty -Name $a.Name -ErrorAction SilentlyContinue)) {
      $off = Get-NetOffValue $p.DisplayName $p.DisplayValue $p.ValidDisplayValues
      if (-not $off) { continue }
      $group = Get-NetGroup $p.DisplayName
      $why = $NetWhy[$p.DisplayName]
      if (-not $why -and $p.DisplayName -match 'Checksum') { $why = $NetChecksumWhy }
      if (-not $why) { $why = 'Adapter power saving. Turning it off keeps the link up and responsive.' }
      [void]$rows.Add([pscustomobject]@{
        Kind = 'Property'; Adapter = $a.Name; Setting = $p.DisplayName
        Current = $p.DisplayValue; Target = $off; Why = $why; Group = $group
      })
    }
    $pm = try { Get-NetAdapterPowerManagement -Name $a.Name -ErrorAction Stop } catch { $null }
    if ($pm -and $pm.AllowComputerToTurnOffDevice -eq 'Enabled') {
      [void]$rows.Add([pscustomobject]@{
        Kind = 'Power'; Adapter = $a.Name; Setting = 'Allow the computer to turn off this device'
        Current = 'Enabled'; Target = 'Disabled'; Group = 'Power saving'
        Why = 'Windows may power the adapter down to save energy. This is the classic cause of "the internet drops after the PC has been idle".'
      })
    }
  }

  # a leftover from old tweak guides that switches every offload off system-wide
  $dto = (Get-ItemProperty $TcpipKey -ErrorAction SilentlyContinue).DisableTaskOffload
  if ($dto -eq 1) {
    [void]$rows.Add([pscustomobject]@{
      Kind = 'TaskOffload'; Adapter = 'All adapters'; Setting = 'DisableTaskOffload (registry)'
      Current = '1'; Target = 'Removed'; Group = 'Repair'
      Why = 'A leftover tweak that turns off every offload for the whole system. It also stops Receive Side Scaling from spreading network work across CPU cores. Removing it restores the Windows default. Takes effect after a restart.'
    })
  }

  $order = @{ 'Repair' = 0; 'Power saving' = 1; 'Latency (optional)' = 2 }
  $rows | Sort-Object { $order[$_.Group] }
}

function Get-NetNotes {
  $n = New-Object System.Collections.ArrayList
  foreach ($a in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Not Present' })) {
    [void]$n.Add(("{0}: {1}, link {2}, {3}" -f $a.Name, $a.InterfaceDescription, $a.LinkSpeed, $a.Status))

    $speeds = (Get-NetAdapterAdvancedProperty -Name $a.Name -DisplayName 'Speed & Duplex' -ErrorAction SilentlyContinue).ValidDisplayValues
    # $a.Speed is bits per second; LinkSpeed is a display string
    if ($speeds -and ($speeds -match '2\.5 Gbps') -and $a.Speed -eq 1000000000) {
      [void]$n.Add('    [i] Adapter supports 2.5 Gbps, negotiated 1 Gbps. That is the switch or the cable, not a setting.')
    }
    $pm = try { Get-NetAdapterPowerManagement -Name $a.Name -ErrorAction Stop } catch { $null }
    if (-not $pm) {
      [void]$n.Add('    [i] Power settings unreadable (common on Realtek). Check by hand: Device Manager, adapter, Power Management tab.')
    }

    # Receive Side Scaling spreads network work across CPU cores
    $rss = try { Get-NetAdapterRss -Name $a.Name -ErrorAction Stop } catch { $null }
    if (-not $rss) {
      [void]$n.Add('    [i] No RSS on this adapter or driver: network work stays on one core. Fine for gaming.')
    } elseif (-not $rss.Enabled) {
      [void]$n.Add('    [!] RSS off: network work stuck on one core. Turn it on in the adapter''s Advanced tab.')
    } elseif (@($rss.IndirectionTable).Count -eq 0) {
      [void]$n.Add('    [!] RSS on but its indirection table is empty - usually a DisableTaskOffload leftover or a filter driver (ExitLag in filter mode).')
    } else {
      [void]$n.Add(("    [ok] RSS: on, {0} queue(s), processors {1}-{2}, profile {3}." -f $rss.NumberOfReceiveQueues, $rss.BaseProcessorNumber, $rss.MaxProcessorNumber, $rss.Profile))
    }

    $rb = (Get-NetAdapterAdvancedProperty -Name $a.Name -DisplayName 'Receive Buffers' -ErrorAction SilentlyContinue).DisplayValue
    $tb = (Get-NetAdapterAdvancedProperty -Name $a.Name -DisplayName 'Transmit Buffers' -ErrorAction SilentlyContinue).DisplayValue
    if ($rb -or $tb) {
      [void]$n.Add(("    [i] Buffers: receive {0}, transmit {1}. Lower only if chasing stutter - too low drops packets in bursts." -f $(if ($rb) { $rb } else { '-' }), $(if ($tb) { $tb } else { '-' })))
    }
  }
  [void]$n.Add('')
  [void]$n.Add('Driver: take it from the chip maker (Intel, Realtek, Marvell), not the motherboard page. RSS often needs their latest.')
  [void]$n.Add('Latency options follow Microsoft''s network adapter performance tuning guide.')
  [void]$n.Add('')
  [void]$n.Add('Applying a change resets the adapter: the link drops for a second or two. Not mid-download, not over remote desktop.')
  [void]$n.Add('On battery, leave these alone - that is what they are for.')
  return $n
}

function Invoke-NetFix($Row) {
  if (-not (Test-Admin)) { throw 'needs Administrator' }
  if ($Row.Kind -eq 'TaskOffload') {
    Add-UndoEntry ([pscustomobject]@{
      Type = 'TcpipReg'; Name = 'DisableTaskOffload'; Previous = $Row.Current; When = (Get-Date).ToString('s') })
    Remove-ItemProperty -Path $TcpipKey -Name DisableTaskOffload -ErrorAction Stop
  } elseif ($Row.Kind -eq 'Property') {
    Add-UndoEntry ([pscustomobject]@{
      Type = 'NetProperty'; Adapter = $Row.Adapter; Name = $Row.Setting
      Previous = $Row.Current; When = (Get-Date).ToString('s') })
    Set-NetAdapterAdvancedProperty -Name $Row.Adapter -DisplayName $Row.Setting -DisplayValue $Row.Target -ErrorAction Stop
  } else {
    Add-UndoEntry ([pscustomobject]@{
      Type = 'NetPower'; Adapter = $Row.Adapter; Name = 'AllowComputerToTurnOffDevice'
      Previous = $Row.Current; When = (Get-Date).ToString('s') })
    $pm = Get-NetAdapterPowerManagement -Name $Row.Adapter -ErrorAction Stop
    $pm.AllowComputerToTurnOffDevice = 'Disabled'
    Set-NetAdapterPowerManagement -InputObject $pm -ErrorAction Stop
  }
}

# --- app optimizer ----------------------------------------------------------
function Get-AppPlans {
  @(
    [pscustomobject]@{ Name = 'Discord'; Process = 'Discord'; Match = 'Discord'; Cache = @(
      (Join-Path $env:APPDATA 'discord\Cache'),
      (Join-Path $env:APPDATA 'discord\Code Cache'),
      (Join-Path $env:APPDATA 'discord\GPUCache'),
      (Join-Path $env:LOCALAPPDATA 'Discord\Cache')) }
    [pscustomobject]@{ Name = 'Spotify'; Process = 'Spotify'; Match = 'Spotify'; Cache = @(
      (Join-Path $env:LOCALAPPDATA 'Spotify\Data'),
      (Join-Path $env:LOCALAPPDATA 'Spotify\Storage')) }
  )
}

function Get-AppStartupEntries {
  $entries = New-Object System.Collections.ArrayList
  foreach ($key in @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run')) {
    if (-not (Test-Path $key)) { continue }
    $item = Get-ItemProperty $key -ErrorAction SilentlyContinue
    foreach ($name in $item.PSObject.Properties.Name) {
      if ($name -in 'PSPath','PSParentPath','PSChildName','PSDrive','PSProvider') { continue }
      [void]$entries.Add([pscustomobject]@{ Key = $key; Name = $name; Data = [string]$item.$name })
    }
  }
  $entries
}

function Get-AppFindings {
  $startup = @(Get-AppStartupEntries)
  $rows = New-Object System.Collections.ArrayList
  foreach ($app in Get-AppPlans) {
    $start = @($startup | Where-Object { $_.Name -match $app.Match -or $_.Data -match $app.Match }) | Select-Object -First 1
    $processes = @(Get-Process -Name $app.Process -ErrorAction SilentlyContinue)
    $cache = @($app.Cache | Where-Object { Test-Path $_ } | Select-Object -Unique)
    if ($start) {
      [void]$rows.Add([pscustomobject]@{
        App = $app.Name; Action = 'Startup'; Status = 'Enabled'; Target = 'Disabled'
        Effect = 'Stops it opening with Windows. Launch it normally when you need it.'
        Why = "Startup entry: $($start.Name)"; Data = $start; Plan = $app
      })
    }
    if ($processes.Count -gt 0) {
      [void]$rows.Add([pscustomobject]@{
        App = $app.Name; Action = 'Close'; Status = "$($processes.Count) process(es) running"; Target = 'Closed'
        Effect = 'Frees the app''s current RAM/CPU. It will reopen when you launch it.'
        Why = 'The app is currently running.'; Data = $null; Plan = $app
      })
    }
    if ($cache.Count -gt 0) {
      [void]$rows.Add([pscustomobject]@{
        App = $app.Name; Action = 'Cache'; Status = "$($cache.Count) folder(s) present"; Target = 'Removed'
        Effect = 'Frees disk space. The app rebuilds this cache; it is not a permanent speed boost.'
        Why = ('Rebuildable cache: {0}' -f ($cache -join ', ')); Data = $cache; Plan = $app
      })
    }
  }
  $rows
}

function Invoke-AppAction($Row) {
  if ($Row.Action -eq 'Startup') {
    if (-not (Test-Admin) -and $Row.Data.Key -like 'HKLM:*') { throw 'disabling this startup entry needs Administrator' }
    Add-UndoEntry ([pscustomobject]@{ Type = 'AppStartup'; Key = $Row.Data.Key; Name = $Row.Data.Name; Data = $Row.Data.Data; When = (Get-Date).ToString('s') })
    Remove-ItemProperty -Path $Row.Data.Key -Name $Row.Data.Name -ErrorAction Stop
    return
  }
  if ($Row.Action -eq 'Close') {
    Get-Process -Name $Row.Plan.Process -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction Stop
    return
  }
  if (@(Get-Process -Name $Row.Plan.Process -ErrorAction SilentlyContinue).Count -gt 0) { throw "Close $($Row.App) before clearing its cache" }
  foreach ($dir in $Row.Data) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
}

# --- small drawing helpers ---------------------------------------------------
function New-RoundPath($Rect, [int]$Radius) {
  $d = $Radius * 2
  $p = New-Object Drawing.Drawing2D.GraphicsPath
  $p.AddArc($Rect.X, $Rect.Y, $d, $d, 180, 90)
  $p.AddArc($Rect.Right - $d, $Rect.Y, $d, $d, 270, 90)
  $p.AddArc($Rect.Right - $d, $Rect.Bottom - $d, $d, $d, 0, 90)
  $p.AddArc($Rect.X, $Rect.Bottom - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  $p
}

function Set-Rounded($Ctrl, [int]$Radius) {
  $apply = {
    $r = New-Object Drawing.Rectangle(0, 0, $Ctrl.Width, $Ctrl.Height)
    $path = New-RoundPath $r $Radius
    $Ctrl.Region = New-Object Drawing.Region($path)
    $path.Dispose()
  }.GetNewClosure()
  & $apply
  $Ctrl.Add_Resize($apply)
}

function Shift-Color($C, [int]$Amount) {
  [Drawing.Color]::FromArgb($C.A,
    [Math]::Max(0, [Math]::Min(255, [int]$C.R + $Amount)),
    [Math]::Max(0, [Math]::Min(255, [int]$C.G + $Amount)),
    [Math]::Max(0, [Math]::Min(255, [int]$C.B + $Amount)))
}

# Flat button painted by hand. $Bg is whatever sits behind it, so the rounded
# corners antialias against it instead of being clipped square by a region. The
# border darkens toward the bottom edge, which is what gives it a little lift.
function Set-FluentButton($Btn, $Fill, $Border, $Fore, $Bg, [int]$Radius) {
  $Btn.FlatStyle = 'Flat'
  $Btn.FlatAppearance.BorderSize = 0
  $Btn.FlatAppearance.MouseOverBackColor = $Bg
  $Btn.FlatAppearance.MouseDownBackColor = $Bg
  $Btn.BackColor = $Bg
  $Btn.ForeColor = $Fore
  $Btn.UseVisualStyleBackColor = $false
  $Btn.Region = $null
  $state = New-Object psobject -Property @{ Hot = $false; Down = $false }
  # light fills darken on hover, dark fills lighten
  $light = ([int]$Fill.R + $Fill.G + $Fill.B) -gt 600

  $Btn.Add_MouseEnter({ $state.Hot = $true;  $Btn.Invalidate() }.GetNewClosure())
  $Btn.Add_MouseLeave({ $state.Hot = $false; $state.Down = $false; $Btn.Invalidate() }.GetNewClosure())
  $Btn.Add_MouseDown({ $state.Down = $true;  $Btn.Invalidate() }.GetNewClosure())
  $Btn.Add_MouseUp({   $state.Down = $false; $Btn.Invalidate() }.GetNewClosure())

  $Btn.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.Clear($Bg)
    $g.SmoothingMode = 'AntiAlias'
    $rect = New-Object Drawing.Rectangle(0, 0, ($s.Width - 1), ($s.Height - 1))
    $path = New-RoundPath $rect $Radius

    $f = $Fill
    if ($state.Down)    { $f = Shift-Color $Fill $(if ($light) { -14 } else { -18 }) }
    elseif ($state.Hot) { $f = Shift-Color $Fill $(if ($light) { -6 } else { 14 }) }
    $fill = New-Object Drawing.SolidBrush($f)
    $g.FillPath($fill, $path)

    $edge = New-Object Drawing.Drawing2D.LinearGradientBrush($rect, $Border, (Shift-Color $Border -26), 90)
    $pen = New-Object Drawing.Pen($edge, 1)
    $g.DrawPath($pen, $path)

    # the focus ring: without it, tabbing through the app shows nothing at all
    if ($s.Focused) {
      $ring = New-Object Drawing.Rectangle(3, 3, ($s.Width - 7), ($s.Height - 7))
      $rp = New-RoundPath $ring ([Math]::Max(1, $Radius - 2))
      $rpen = New-Object Drawing.Pen($Fore, 1)
      $g.DrawPath($rpen, $rp)
      $rpen.Dispose(); $rp.Dispose()
    }

    $fore = if ($s.Enabled) { $s.ForeColor } else { [Drawing.Color]::FromArgb(150, $s.ForeColor) }
    [Windows.Forms.TextRenderer]::DrawText($g, $s.Text, $s.Font, $s.ClientRectangle, $fore,
      [Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter, SingleLine, EndEllipsis')

    $fill.Dispose(); $edge.Dispose(); $pen.Dispose(); $path.Dispose()
  }.GetNewClosure())
}

# Windows fixes both the width and the colour of a real scrollbar, so lists and
# report panes hide theirs and get this drawn one instead: a 12px lane, a 6px
# thumb that tracks the control's own scroll position, and no lane at all while
# everything fits.
function Add-SlimScrollbar($Ctrl, $Track, $Thumb, $ThumbHot, [double]$Scale = 1) {
  $EM_GETLINECOUNT = 0x00BA; $EM_LINESCROLL = 0x00B6; $EM_GETFIRSTVISIBLELINE = 0x00CE
  $LVM_GETTOPINDEX = 0x1027; $LVM_GETCOUNTPERPAGE = 0x1028
  $isList = $Ctrl -is [Windows.Forms.ListView]

  $Ctrl.Width = $Ctrl.Width - 16          # leave a lane for the bar
  $arrowZone = [int](13 * $Scale)          # hit area for the little end arrows
  $thumbW = [int](6 * $Scale)
  $tri = [int](4 * $Scale)
  $bar = New-Object Windows.Forms.Panel
  $bar.Bounds = New-Object Drawing.Rectangle(($Ctrl.Right + 3), ($Ctrl.Top + 2), 12, ($Ctrl.Height - 4))
  # never anchor left as well as right: an 8px bar stretched between both edges
  # collapses to nothing when the window narrows
  $anchor = [Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Right
  if ($Ctrl.Anchor -band [Windows.Forms.AnchorStyles]::Bottom) { $anchor = $anchor -bor [Windows.Forms.AnchorStyles]::Bottom }
  $bar.Anchor = $anchor
  $bar.BackColor = $Track
  $Ctrl.Parent.Controls.Add($bar)
  $bar.BringToFront()

  $st = New-Object psobject -Property @{ Hot = $false; Drag = $false; GrabY = 0; ThumbTop = 0; Last = '' }

  # total rows, how many fit, and the first one showing
  $metrics = {
    if ($isList) {
      $total = $Ctrl.Items.Count
      $per   = [int][TsakasNative]::SendMessage($Ctrl.Handle, $LVM_GETCOUNTPERPAGE, [IntPtr]::Zero, [IntPtr]::Zero)
      $first = [int][TsakasNative]::SendMessage($Ctrl.Handle, $LVM_GETTOPINDEX, [IntPtr]::Zero, [IntPtr]::Zero)
    } else {
      $total = [int][TsakasNative]::SendMessage($Ctrl.Handle, $EM_GETLINECOUNT, [IntPtr]::Zero, [IntPtr]::Zero)
      $per   = [int]($Ctrl.ClientSize.Height / [Math]::Max(1, $Ctrl.Font.Height))
      $first = [int][TsakasNative]::SendMessage($Ctrl.Handle, $EM_GETFIRSTVISIBLELINE, [IntPtr]::Zero, [IntPtr]::Zero)
    }
    @{ Total = [Math]::Max(1, $total); Per = [Math]::Max(1, $per); First = [Math]::Max(0, $first) }
  }.GetNewClosure()

  $trackTop    = { $arrowZone }.GetNewClosure()
  $trackHeight = { [Math]::Max(1, ($bar.Height - 2 * $arrowZone)) }.GetNewClosure()
  $thumbHeight = { param($m) [Math]::Max([int](22 * $Scale), [int]((& $trackHeight) * $m.Per / $m.Total)) }.GetNewClosure()

  $scrollTo = {
    param($line)
    $m = & $metrics
    $target = [Math]::Max(0, [Math]::Min([int]$line, ($m.Total - $m.Per)))
    if ($isList) {
      if ($Ctrl.Items.Count -gt 0) {
        $Ctrl.EnsureVisible([Math]::Min(($Ctrl.Items.Count - 1), ($target + $m.Per - 1)))
        $Ctrl.EnsureVisible($target)
      }
    } else {
      [void][TsakasNative]::SendMessage($Ctrl.Handle, $EM_LINESCROLL, [IntPtr]::Zero, [IntPtr]($target - $m.First))
    }
  }.GetNewClosure()

  $bar.Add_Paint({
    param($s2, $e)
    $m = & $metrics
    $g = $e.Graphics
    $g.Clear($Track)
    if ($m.Total -le $m.Per) { return }        # everything fits: no bar at all
    $g.SmoothingMode = 'AntiAlias'
    $colour = $(if ($st.Hot -or $st.Drag) { $ThumbHot } else { $Thumb })

    # thumb: 6px wide, centred in the lane, fully rounded ends
    $h = & $thumbHeight $m
    $st.ThumbTop = (& $trackTop) + [int](((& $trackHeight) - $h) * $m.First / ($m.Total - $m.Per))
    # a capsule: round cap, straight body, round cap. New-RoundPath cannot do this
    # shape, because its arcs collapse when the width equals twice the radius.
    $x = [int]($s2.Width / 2) - [int]($thumbW / 2)
    $b = New-Object Drawing.SolidBrush($colour)
    $g.FillEllipse($b, $x, $st.ThumbTop, $thumbW, $thumbW)
    $g.FillEllipse($b, $x, ($st.ThumbTop + $h - $thumbW), $thumbW, $thumbW)
    $g.FillRectangle($b, $x, ($st.ThumbTop + [int]($thumbW / 2)), $thumbW, [Math]::Max(1, ($h - $thumbW)))

    # a small triangle at each end
    $mid = [int]($s2.Width / 2)
    $up = @(
      (New-Object Drawing.Point($mid, $tri)),
      (New-Object Drawing.Point(($mid - $tri), ($tri * 2 + 1))),
      (New-Object Drawing.Point(($mid + $tri), ($tri * 2 + 1))))
    $down = @(
      (New-Object Drawing.Point($mid, ($s2.Height - $tri))),
      (New-Object Drawing.Point(($mid - $tri), ($s2.Height - $tri * 2 - 1))),
      (New-Object Drawing.Point(($mid + $tri), ($s2.Height - $tri * 2 - 1))))
    $g.FillPolygon($b, $up)
    $g.FillPolygon($b, $down)
    $b.Dispose()
  }.GetNewClosure())

  $bar.Add_MouseEnter({ $st.Hot = $true; $bar.Invalidate() }.GetNewClosure())
  $bar.Add_MouseLeave({ $st.Hot = $false; $bar.Invalidate() }.GetNewClosure())
  $bar.Add_MouseUp({ $st.Drag = $false; $bar.Invalidate() }.GetNewClosure())
  $bar.Add_MouseDown({
    param($s2, $e)
    $m = & $metrics
    if ($m.Total -le $m.Per) { return }
    $h = & $thumbHeight $m
    if ($e.Y -lt $arrowZone) { & $scrollTo ($m.First - 3); $bar.Invalidate(); return }
    if ($e.Y -gt ($s2.Height - $arrowZone)) { & $scrollTo ($m.First + 3); $bar.Invalidate(); return }
    if ($e.Y -ge $st.ThumbTop -and $e.Y -le ($st.ThumbTop + $h)) {
      $st.Drag = $true
      $st.GrabY = $e.Y - $st.ThumbTop
      return
    }
    & $scrollTo (($e.Y - (& $trackTop) - $h / 2) * ($m.Total - $m.Per) / [Math]::Max(1, ((& $trackHeight) - $h)))
    $bar.Invalidate()
  }.GetNewClosure())
  $bar.Add_MouseMove({
    param($s2, $e)
    if (-not $st.Drag) { return }
    $m = & $metrics
    $h = & $thumbHeight $m
    & $scrollTo (($e.Y - $st.GrabY - (& $trackTop)) * ($m.Total - $m.Per) / [Math]::Max(1, ((& $trackHeight) - $h)))
    $bar.Invalidate()
  }.GetNewClosure())

  # the control scrolls itself too (wheel, keys, selection), so keep the thumb in
  # step; repaint only when something actually moved
  $sync = {
    if (-not $bar.IsHandleCreated) { return }
    # the network list hides itself when there is nothing to show
    # SB_BOTH: columns are sized to fit, so there is nothing to scroll sideways
    if ($isList) { [void][TsakasNative]::ShowScrollBar($Ctrl.Handle, 3, $false) }
    $m = & $metrics
    $bar.Visible = $Ctrl.Visible -and ($m.Total -gt $m.Per)
    $now = "$($m.Total)/$($m.Per)/$($m.First)"
    if ($now -ne $st.Last) { $st.Last = $now; $bar.Invalidate() }
  }.GetNewClosure()
  $bar | Add-Member -NotePropertyName Sync -NotePropertyValue $sync
  $bar
}

# wraps a control in a padded card and returns the card
function Add-PaddedCard($Ctrl, [int]$Radius, $LineColor, [int]$Pad, $CardColor) {
  $card = New-Object Windows.Forms.Panel
  $card.Location = $Ctrl.Location
  $card.Size = $Ctrl.Size
  $card.Anchor = $Ctrl.Anchor
  $card.BackColor = $CardColor
  $Ctrl.Parent.Controls.Add($card)
  $card.Controls.Add($Ctrl)
  $Ctrl.Location = New-Object Drawing.Point($Pad, $Pad)
  $Ctrl.Size = New-Object Drawing.Size(($card.Width - 2 * $Pad), ($card.Height - 2 * $Pad))
  $Ctrl.Anchor = 'Top,Left,Right,Bottom'
  $Ctrl.BorderStyle = 'None'
  Set-Rounded $card $Radius
  Add-Hairline $card $LineColor $Radius
  $card
}

# a 1px rounded outline drawn by the parent, just outside the control
function Add-Hairline($Ctrl, $Color, [int]$Radius) {
  if (-not $Ctrl.Parent) { return }
  $h = {
    param($s, $e)
    $b = $Ctrl.Bounds
    $b.Inflate(1, 1)
    $e.Graphics.SmoothingMode = 'AntiAlias'
    $path = New-RoundPath $b ($Radius + 1)
    $pen = New-Object Drawing.Pen($Color, 1)
    $e.Graphics.DrawPath($pen, $path)
    $pen.Dispose(); $path.Dispose()
  }.GetNewClosure()
  $Ctrl.Parent.Add_Paint($h)
  $Ctrl.Parent.Invalidate()
}

# --- gui ---------------------------------------------------------------------
function Show-Gui {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing

  $form = New-Object Windows.Forms.Form
  $form.Text = "TsakasOptimizer $Version"
  # Fonts are in points and grow with the display on their own. Everything sized
  # in pixels does not, so it is laid out at 100% and scaled once at the end.
  $probe = $form.CreateGraphics()
  $dpiScale = $probe.DpiX / 96
  $probe.Dispose()
  $sc = { param($n) [int][Math]::Round($n * $dpiScale) }
  $icon = Get-AppIcon
  if ($icon) { $form.Icon = $icon }
  # Open large on a big screen, but never taller than the screen can show: a
  # share of the working area, clamped between the layout minimum and a size
  # that still looks deliberate rather than sprawling.
  # in 100% units, because the whole layout is scaled at the end: the screen is
  # already real pixels, so it is divided back out here and multiplied there
  $area = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $roomW = [int](($area.Width - 40) / $dpiScale)
  $roomH = [int](($area.Height - 60) / $dpiScale)
  $form.ClientSize = New-Object Drawing.Size(
    [Math]::Min($roomW, [Math]::Min(1600, [Math]::Max(1060, [int]($area.Width * 0.72 / $dpiScale)))),
    [Math]::Min($roomH, [Math]::Min(1040, [Math]::Max(640,  [int]($area.Height * 0.82 / $dpiScale)))))
  $form.MinimumSize = New-Object Drawing.Size([Math]::Min($roomW, 980), [Math]::Min($roomH, 620))

  # one place the rest of the layout measures itself against
  $sideW   = 228
  $footerH = 48
  $contentW = $form.ClientSize.Width - $sideW      # width of a section pane
  $contentH = $form.ClientSize.Height - $footerH   # height above the footer
  $ctlW = $contentW - 32                           # a card inside a pane, 12px margins plus room for its border
  $form.StartPosition = 'CenterScreen'

  $accent = [Drawing.Color]::FromArgb(10, 132, 255)   # brighter than the light-theme blue, for contrast on black
  $ink    = [Drawing.Color]::FromArgb(240, 240, 242)
  $muted  = [Drawing.Color]::FromArgb(150, 150, 158)
  $line   = [Drawing.Color]::FromArgb(42, 42, 48)
  $panel  = [Drawing.Color]::FromArgb(15, 15, 17)      # matte black, not pure black
  $card   = [Drawing.Color]::FromArgb(24, 24, 27)      # panels sit one step above the ground
  $white  = [Drawing.Color]::White                     # only for text on the accent
  $accentFill = [Drawing.Color]::FromArgb(0, 95, 184)  # white on this is 6.3:1; on $accent it is 3.7:1
  $form.BackColor = $panel
  $form.ForeColor = $ink

  # Segoe UI Variable ships one face per optical size on Windows 11. Use the face
  # meant for each size rather than scaling one family, and fall back on older builds.
  $pickFamily = {
    param($name, $fallback)
    try {
      $probe = New-Object Drawing.Font($name, 9)
      $ok = ($probe.Name -eq $name)
      $probe.Dispose()
      if ($ok) { return $name }
    } catch { }
    return $fallback
  }
  $family  = & $pickFamily 'Segoe UI Variable Text' 'Segoe UI'
  $small   = & $pickFamily 'Segoe UI Variable Small' $family
  $semi    = & $pickFamily 'Segoe UI Variable Text Semibold' (& $pickFamily 'Segoe UI Semibold' 'Segoe UI')
  $display = & $pickFamily 'Segoe UI Variable Display Semib' (& $pickFamily 'Segoe UI Semibold' 'Segoe UI')
  $form.Font = New-Object Drawing.Font($family, 10)

  $btnEdge = [Drawing.Color]::FromArgb(58, 58, 64)
  $flat = {
    param($b, $primary)
    $b.Cursor = 'Hand'
    $b.Height = 34
    if ($primary) {
      $b.Font = New-Object Drawing.Font($semi, 10)
      Set-FluentButton $b $accentFill (Shift-Color $accentFill -18) $white $panel 6
    } else {
      Set-FluentButton $b ([Drawing.Color]::FromArgb(33, 33, 38)) $btnEdge $ink $panel 6
    }
  }

  # A message box is a system window and always paints light, so dialogs are
  # built here instead. Returns the same DialogResult a message box would.
  $dialog = {
    param($text, $title, $buttons)
    $d = New-Object Windows.Forms.Form
    $d.Text = $title
    $d.FormBorderStyle = 'FixedDialog'
    $d.MaximizeBox = $false
    $d.MinimizeBox = $false
    $d.ShowInTaskbar = $false
    $d.StartPosition = 'CenterParent'
    $d.BackColor = $panel
    $d.ForeColor = $ink
    $d.Font = New-Object Drawing.Font($family, 10)

    $lbl = New-Object Windows.Forms.Label
    $lbl.Text = $text
    $lbl.AutoSize = $true
    $lbl.MaximumSize = New-Object Drawing.Size(460, 0)
    $lbl.Location = New-Object Drawing.Point(24, 24)
    $lbl.ForeColor = $ink
    $d.Controls.Add($lbl)
    $d.ClientSize = New-Object Drawing.Size([Math]::Max(360, ($lbl.Right + 24)), ($lbl.Bottom + 78))

    $mkDlgButton = {
      param($caption, $result, $primary, $x)
      $b = New-Object Windows.Forms.Button
      $b.Text = $caption
      $b.Size = New-Object Drawing.Size(104, 34)
      $b.Location = New-Object Drawing.Point($x, ($d.ClientSize.Height - 52))
      $b.DialogResult = $result
      & $flat $b $primary
      $d.Controls.Add($b)
      $b
    }
    if ($buttons -eq 'YesNo') {
      $yes = & $mkDlgButton 'Yes' 'Yes' $true ($d.ClientSize.Width - 236)
      $no  = & $mkDlgButton 'No'  'No'  $false ($d.ClientSize.Width - 124)
      $d.AcceptButton = $yes
      $d.CancelButton = $no
    } else {
      $ok = & $mkDlgButton 'OK' 'OK' $true ($d.ClientSize.Width - 124)
      $d.AcceptButton = $ok
      $d.CancelButton = $ok
    }

    try {
      $dark = 1
      $cap = [int]$panel.R -bor ([int]$panel.G -shl 8) -bor ([int]$panel.B -shl 16)
      $txt = [int]$ink.R -bor ([int]$ink.G -shl 8) -bor ([int]$ink.B -shl 16)
      [void][TsakasNative]::DwmSetWindowAttribute($d.Handle, 20, [ref]$dark, 4)
      [void][TsakasNative]::DwmSetWindowAttribute($d.Handle, 35, [ref]$cap, 4)
      [void][TsakasNative]::DwmSetWindowAttribute($d.Handle, 36, [ref]$txt, 4)
    } catch { }

    $result = $d.ShowDialog($form)
    $d.Dispose()
    $result
  }

  # ---- sidebar ----
  $side = New-Object Windows.Forms.Panel
  $side.Location = New-Object Drawing.Point(0, 0)
  $side.Size = New-Object Drawing.Size($sideW, $contentH)
  $side.Anchor = 'Top,Left,Bottom'
  $side.BackColor = $panel
  $form.Controls.Add($side)

  $brandX = 20
  $brandImage = Get-AppIconBitmap $(if ($dpiScale -ge 1.25) { 48 } else { 32 })
  if ($brandImage) {
    $pic = New-Object Windows.Forms.PictureBox
    $pic.SizeMode = 'Zoom'
    $pic.Size = New-Object Drawing.Size(32, 32)
    $pic.Location = New-Object Drawing.Point(18, 24)
    $pic.Image = $brandImage
    $side.Controls.Add($pic)
    $brandX = 58
  }

  $brand = New-Object Windows.Forms.Label
  $brand.Text = 'TsakasOptimizer'
  $brand.Font = New-Object Drawing.Font($display, 12.5)
  $brand.ForeColor = $ink
  $brand.AutoSize = $true
  $brand.Location = New-Object Drawing.Point($brandX, 22)
  $side.Controls.Add($brand)

  $verLabel = New-Object Windows.Forms.Label
  $verLabel.Text = "Version $Version"
  $verLabel.Font = New-Object Drawing.Font($small, 9)
  $verLabel.ForeColor = $muted
  $verLabel.AutoSize = $true
  $verLabel.Location = New-Object Drawing.Point(($brandX + 1), ($brand.Bottom + 1))
  $side.Controls.Add($verLabel)

  # Windows 11 Settings style navigation: a Fluent icon, a soft pill for the
  # selected item and a short accent bar on its left edge
  $iconFamily = & $pickFamily 'Segoe Fluent Icons' (& $pickFamily 'Segoe MDL2 Assets' $null)
  $iconFont = if ($iconFamily) { New-Object Drawing.Font($iconFamily, 11) } else { $null }
  $navFont = New-Object Drawing.Font($family, 10)
  $navIcons = @([char]0xE9D9, [char]0xE964, [char]0xE950, [char]0xE968, [char]0xE8A9)
  $navSelFill = [Drawing.Color]::FromArgb(38, 38, 44)
  $navHoverFill = [Drawing.Color]::FromArgb(28, 28, 33)
  $navState = New-Object psobject -Property @{ Selected = 0; Hover = -1 }

  $navPaint = {
    param($s, $e)
    $g = $e.Graphics
    $g.Clear($panel)
    $g.SmoothingMode = 'AntiAlias'
    $i = [int]$s.Tag
    $sel = ($navState.Selected -eq $i)
    if ($sel -or $navState.Hover -eq $i) {
      $r = New-Object Drawing.Rectangle(0, 0, ($s.Width - 1), ($s.Height - 1))
      $p = New-RoundPath $r 6
      $b = New-Object Drawing.SolidBrush($(if ($sel) { $navSelFill } else { $navHoverFill }))
      $g.FillPath($b, $p); $b.Dispose(); $p.Dispose()
    }
    if ($sel) {
      $bar = New-Object Drawing.Rectangle(0, [int](($s.Height - (& $sc 16)) / 2), (& $sc 3), (& $sc 16))
      $bp = New-RoundPath $bar 1
      $bb = New-Object Drawing.SolidBrush($accent)
      $g.FillPath($bb, $bp); $bb.Dispose(); $bp.Dispose()
    }
    if ($s.Focused) {
      $fr = New-Object Drawing.Rectangle(2, 2, ($s.Width - 5), ($s.Height - 5))
      $fp = New-RoundPath $fr 5
      $fpen = New-Object Drawing.Pen($ink, 1)
      $g.DrawPath($fpen, $fp)
      $fpen.Dispose(); $fp.Dispose()
    }
    $flags = [Windows.Forms.TextFormatFlags]'Left, VerticalCenter, SingleLine, EndEllipsis, NoPadding'
    $textX = & $sc 14
    if ($iconFont) {
      $ir = New-Object Drawing.Rectangle((& $sc 14), 0, (& $sc 22), $s.Height)
      [Windows.Forms.TextRenderer]::DrawText($g, [string]$navIcons[$i], $iconFont, $ir, $(if ($sel) { $accent } else { $ink }), $flags)
      $textX = & $sc 44
    }
    $tr = New-Object Drawing.Rectangle($textX, 0, ($s.Width - $textX - (& $sc 6)), $s.Height)
    [Windows.Forms.TextRenderer]::DrawText($g, $s.Text, $navFont, $tr, $ink, $flags)
  }.GetNewClosure()
  $navFocus = { param($s, $e) $s.Invalidate() }.GetNewClosure()
  $navEnter = { param($s, $e) $navState.Hover = [int]$s.Tag; $s.Invalidate() }.GetNewClosure()
  $navLeave = { param($s, $e) if ($navState.Hover -eq [int]$s.Tag) { $navState.Hover = -1 }; $s.Invalidate() }.GetNewClosure()

  $sections = @(
    @{ Title = 'Processes and services'; Sub = 'Background apps and services worth closing, and the ones worth leaving alone' }
    @{ Title = 'Memory';                 Sub = 'Whether EXPO is really on, and whether the sticks are in the right slots' }
    @{ Title = 'Motherboard';            Sub = 'How old the BIOS is, and which drivers Windows is guessing at' }
    @{ Title = 'Network';                Sub = 'Adapter power saving that quietly costs you latency' }
    @{ Title = 'App Optimizer';          Sub = 'Real startup, memory and disk actions for Discord and Spotify' }
  )

  $panes = @()
  $navs  = @()
  $bodies = @()
  for ($i = 0; $i -lt $sections.Count; $i++) {
    $pane = New-Object Windows.Forms.Panel
    $pane.Location = New-Object Drawing.Point($sideW, 0)
    $pane.Size = New-Object Drawing.Size($contentW, $contentH)
    $pane.Anchor = 'Top,Left,Right,Bottom'
    $pane.BackColor = $panel
    $pane.Visible = ($i -eq 0)
    $form.Controls.Add($pane)

    $head = New-Object Windows.Forms.Label
    $head.Text = $sections[$i].Title
    $head.Font = New-Object Drawing.Font($display, 18)
    $head.ForeColor = $ink
    $head.AutoSize = $true
    $head.Location = New-Object Drawing.Point(12, 12)
    $pane.Controls.Add($head)

    $sub = New-Object Windows.Forms.Label
    $sub.Text = $sections[$i].Sub
    $sub.Font = New-Object Drawing.Font($family, 10)
    $sub.ForeColor = $muted
    $sub.AutoSize = $true
    $sub.Location = New-Object Drawing.Point(14, ($head.Bottom + 2))
    $pane.Controls.Add($sub)

    $bodyTop = $sub.Bottom + 8
    $body = New-Object Windows.Forms.Panel
    $body.Location = New-Object Drawing.Point(0, $bodyTop)
    $body.Size = New-Object Drawing.Size($contentW, ($contentH - $bodyTop - 6))
    $body.Anchor = 'Top,Left,Right,Bottom'
    $body.BackColor = $panel
    $pane.Controls.Add($body)

    $nav = New-Object Windows.Forms.Button
    $nav.Text = $sections[$i].Title
    $nav.Size = New-Object Drawing.Size(200, 36)
    $nav.Location = New-Object Drawing.Point(14, (92 + $i * 40))
    $nav.FlatStyle = 'Flat'
    $nav.FlatAppearance.BorderSize = 0
    $nav.FlatAppearance.MouseOverBackColor = $panel
    $nav.FlatAppearance.MouseDownBackColor = $panel
    $nav.BackColor = $panel
    $nav.UseVisualStyleBackColor = $false
    $nav.Cursor = 'Hand'
    $nav.Tag = $i
    $nav.Add_Paint($navPaint)
    $nav.Add_GotFocus($navFocus)
    $nav.Add_LostFocus($navFocus)
    $nav.Add_MouseEnter($navEnter)
    $nav.Add_MouseLeave($navLeave)
    $side.Controls.Add($nav)

    $panes  += $pane
    $navs   += $nav
    $bodies += $body
  }
  # every pane puts its buttons on the same baseline, measured from its own height
  $bodyH   = $bodies[0].Height
  $btnRowY = $bodyH - 42          # button row

  $tab1 = $bodies[0]
  $tab2 = $bodies[1]
  $tab3 = $bodies[2]
  $tab4 = $bodies[3]
  $tab5 = $bodies[4]

  $selectSection = {
    param($index)
    for ($k = 0; $k -lt $panes.Count; $k++) { $panes[$k].Visible = ($k -eq $index) }
    $navState.Selected = $index
    foreach ($n in $navs) { $n.Invalidate() }
    $form.Cursor = 'WaitCursor'
    try {
      if ($index -eq 2 -and -not $script:boardLoaded) { & $loadBoard; $script:boardLoaded = $true }
      if ($index -eq 3 -and -not $script:netLoaded)   { & $loadNet;   $script:netLoaded   = $true }
      if ($index -eq 4 -and -not $script:appLoaded)   { & $loadApps;  $script:appLoaded  = $true }
    } finally { $form.Cursor = 'Default' }
  }
  foreach ($n in $navs) { $n.Add_Click({ param($s, $e) & $selectSection ([int]$s.Tag) }) }

  $lv = New-Object Windows.Forms.ListView
  $lv.View = 'Details'; $lv.CheckBoxes = $true; $lv.FullRowSelect = $true; $lv.HideSelection = $false
  $lv.Location = New-Object Drawing.Point(12, 12)
  $lv.Size = New-Object Drawing.Size($ctlW, ($btnRowY - 152))
  $lv.Anchor = 'Top,Left,Right,Bottom'
  $lv.BorderStyle = 'FixedSingle'
  $lv.BackColor = $card
  [void]$lv.Columns.Add('App Name', 330)
  [void]$lv.Columns.Add('Type', 70)
  [void]$lv.Columns.Add('RAM', 90)
  [void]$lv.Columns.Add('Suggested', 290)
  $tab1.Controls.Add($lv)

  $details = New-Object Windows.Forms.TextBox
  $details.Multiline = $true; $details.ReadOnly = $true; $details.BackColor = $card
  $details.Location = New-Object Drawing.Point(12, ($btnRowY - 110))
  $details.Size = New-Object Drawing.Size($ctlW, 56)
  $details.Anchor = 'Left,Right,Bottom'
  $details.BorderStyle = 'FixedSingle'
  $details.ForeColor = $muted
  $details.Text = 'Scans the processes your CPU/PC runs. Suggests putting services on Manual instead of Automatic and closing apps you are not using. Tick what you want changed, then press Apply.'
  $tab1.Controls.Add($details)

  $status = New-Object Windows.Forms.Label
  $status.Location = New-Object Drawing.Point(12, ($btnRowY - 44))
  $status.Size = New-Object Drawing.Size($ctlW, 40)
  $status.Anchor = 'Left,Right,Bottom'
  $status.ForeColor = $muted
  $tab1.Controls.Add($status)

  $mkButton = {
    param($text, $x, $w)
    $b = New-Object Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object Drawing.Point($x, $btnRowY)
    $b.Size = New-Object Drawing.Size($w, 30)
    $b.Anchor = 'Left,Bottom'
    & $flat $b $false
    $tab1.Controls.Add($b)
    $b
  }
  $btnApply   = & $mkButton 'Apply selected' 12  130
  $btnRefresh = & $mkButton 'Rescan'         150 90
  $btnUndo    = & $mkButton 'Undo changes'   248 124
  $btnElev    = & $mkButton 'Restart app as admin' 380 160
  & $flat $btnApply $true
  $btnElev.Visible = -not (Test-Admin)
  $btnElev.Anchor = 'Bottom,Right'
  $btnElev.Location = New-Object Drawing.Point(($tab1.ClientSize.Width - $btnElev.Width - 12), $btnRowY)

  $refresh = {
    $lv.Items.Clear()
    foreach ($f in @(Get-Findings)) {
      $it = New-Object Windows.Forms.ListViewItem($f.Label + $(if ($f.Count -gt 1) { " x$($f.Count)" } else { '' }))
      [void]$it.SubItems.Add($f.Type)
      [void]$it.SubItems.Add($(if ($f.RamMB -gt 0) { '{0} MB' -f $f.RamMB } else { '-' }))
      [void]$it.SubItems.Add($(if ($f.Action -eq 'Kill') { 'Close' } else { 'Set to Manual' }))
      $it.Tag = $f
      [void]$lv.Items.Add($it)
    }
    $status.Text = "{0} item(s) found.{1}" -f $lv.Items.Count,
      $(if (Test-Admin) { '' } else { '  Not running as administrator - service changes will be skipped.' })
  }
  & $refresh

  $lv.Add_ItemSelectionChanged({
    if ($lv.SelectedItems.Count -gt 0) {
      $f = $lv.SelectedItems[0].Tag
      $details.Text = "{0}`r`n{1}" -f $f.Why,
        $(if ($f.Action -eq 'Kill') { 'Closing it now. It starts again next time you open the app.' }
          else { 'Start type becomes Manual: Windows starts it only when something asks for it. Reversible with Undo.' })
    }
  })

  # ---- footer: contact on the left, update check on the right ----
  $footer = New-Object Windows.Forms.Panel
  $footer.Location = New-Object Drawing.Point(0, $contentH)
  $footer.Size = New-Object Drawing.Size($form.ClientSize.Width, $footerH)
  $footer.Anchor = 'Left,Right,Bottom'
  $footer.BackColor = $panel
  $footerLine = $line
  $footer.Add_Paint({
    param($s, $e)
    $pen = New-Object Drawing.Pen($footerLine, 1)
    $e.Graphics.DrawLine($pen, 0, 0, $s.Width, 0)
    $pen.Dispose()
  }.GetNewClosure())
  $form.Controls.Add($footer)

  $contact = New-Object Windows.Forms.LinkLabel
  $contact.AutoSize = $true
  $contact.Location = New-Object Drawing.Point(14, 16)
  $contact.Font = New-Object Drawing.Font($small, 9.5)
  $contact.Text = 'Need advice for your rig?  Discord: _tsakas_    X: @TsakasIoannis'
  $contact.ForeColor = $muted
  $contact.LinkColor = $accent
  $contact.ActiveLinkColor = $accent
  $contact.LinkBehavior = 'HoverUnderline'
  $contact.LinkArea = New-Object Windows.Forms.LinkArea($contact.Text.IndexOf('@TsakasIoannis'), 14)
  $contact.Add_LinkClicked({ Start-Process 'https://x.com/TsakasIoannis' })
  $footer.Controls.Add($contact)

  $btnUpdate = New-Object Windows.Forms.Button
  $btnUpdate.Text = 'Check for updates'
  $btnUpdate.Size = New-Object Drawing.Size(150, 30)
  $btnUpdate.Location = New-Object Drawing.Point(($footer.Width - 164), 9)
  $btnUpdate.Anchor = 'Bottom,Right'
  & $flat $btnUpdate $false
  $footer.Controls.Add($btnUpdate)

  # blue dot = a newer version is published online
  $dot = New-Object Windows.Forms.Label
  $dot.Text = [char]0x25CF
  $dot.Font = New-Object Drawing.Font('Segoe UI', 14)
  $dot.ForeColor = $accent
  $dot.AutoSize = $true
  $dot.Visible = $false
  $dot.Location = New-Object Drawing.Point(($footer.Width - 186), 11)
  $dot.Anchor = 'Bottom,Right'
  $footer.Controls.Add($dot)

  $tip = New-Object Windows.Forms.ToolTip
  $tip.SetToolTip($dot, 'A newer version is available - click Check for updates.')

  $scriptPath = $PSCommandPath
  $online = $null

  # check after the window is up, so startup is not blocked
  $timer = New-Object Windows.Forms.Timer
  $timer.Interval = 1500
  $timer.Add_Tick({
    $timer.Stop()
    $script:online = Get-OnlineRelease
    if ($script:online -and ([version]$script:online.Version -gt [version]$Version)) { $dot.Visible = $true }
  })
  $timer.Start()

  $btnUpdate.Add_Click({
    if (-not $scriptPath) {
      [void](& $dialog "You launched this straight from GitHub, so you are already on the latest version ($Version)." 'Up to date' 'OK')
      return
    }
    $btnUpdate.Enabled = $false
    $form.Cursor = 'WaitCursor'
    try { $script:online = Get-OnlineRelease } finally { $form.Cursor = 'Default'; $btnUpdate.Enabled = $true }

    if (-not $script:online) {
      [void](& $dialog "Could not reach $Repo on GitHub. Check your connection, or download the latest copy yourself." 'Update check failed' 'OK')
      return
    }
    if ([version]$script:online.Version -le [version]$Version) {
      $dot.Visible = $false
      [void](& $dialog "You are on the latest version ($Version)." 'Up to date' 'OK')
      return
    }
    $ans = & $dialog "Version $($script:online.Version) is available (you have $Version).`r`n`r`nDownload it and restart TsakasOptimizer?" 'Update available' 'YesNo'
    if ($ans -ne 'Yes') { return }
    try {
      Install-Update $script:online.Text
      Start-Process powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $scriptPath)
      $form.Close()
    } catch {
      [void](& $dialog "Update failed: $($_.Exception.Message)" 'Update failed' 'OK')
    }
  })

  $btnRefresh.Add_Click({ & $refresh })

  $btnApply.Add_Click({
    $items = @($lv.CheckedItems)
    if ($items.Count -eq 0) {
      [void](& $dialog 'Tick at least one row first.' 'TsakasOptimizer' 'OK')
      return
    }
    $names = ($items | ForEach-Object { $_.Tag.Label }) -join "`r`n"
    $ans = & $dialog "Apply to these $($items.Count) item(s)?`r`n`r`n$names" 'TsakasOptimizer' 'YesNo'
    if ($ans -ne 'Yes') { return }

    $freed = 0.0; $errs = @()
    foreach ($it in $items) {
      try { $freed += Invoke-Finding $it.Tag }
      catch { $errs += "{0}: {1}" -f $it.Tag.Label, $_.Exception.Message }
    }
    & $refresh
    $status.Text = "Freed about {0} MB.{1}" -f [math]::Round($freed, 1),
      $(if ($errs) { "  Failed: " + ($errs -join ' | ') } else { '' })
  })

  $btnUndo.Add_Click({
    if (-not (Test-Path $UndoFile)) { $status.Text = 'Nothing to undo.'; return }
    if (-not (Test-Admin)) { $status.Text = 'Restart as administrator to undo service changes.'; return }
    Invoke-Undo
    & $refresh
    $status.Text = 'Service start types restored.'
  })

  $btnElev.Add_Click({
    Start-Process powershell -Verb RunAs -ArgumentList @(
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $PSCommandPath)
    $form.Close()
  })

  # ---- Memory tab ----
  $mlv = New-Object Windows.Forms.ListView
  $mlv.View = 'Details'; $mlv.FullRowSelect = $true
  $mlv.Location = New-Object Drawing.Point(12, 12)
  $mlv.Size = New-Object Drawing.Size($ctlW, 130)
  $mlv.Anchor = 'Top,Left,Right'
  $mlv.BorderStyle = 'FixedSingle'
  $mlv.BackColor = $card
  foreach ($c in @(@('Slot', 170), @('Size', 60), @('Type', 60), @('Rated', 80), @('Running', 80), @('Timings', 90), @('Part', 230))) {
    [void]$mlv.Columns.Add($c[0], $c[1])
  }
  $tab2.Controls.Add($mlv)

  $mtext = New-Object Windows.Forms.TextBox
  $mtext.Multiline = $true; $mtext.ReadOnly = $true; $mtext.ScrollBars = 'None'
  $mtext.BackColor = $card
  $mtext.Font = New-Object Drawing.Font('Consolas', 9)
  $mtext.Location = New-Object Drawing.Point(12, 152)
  $mtext.Size = New-Object Drawing.Size($ctlW, ($btnRowY - 162))
  $mtext.Anchor = 'Top,Left,Right,Bottom'
  $mtext.BorderStyle = 'FixedSingle'
  $mtext.ForeColor = $ink
  $tab2.Controls.Add($mtext)

  $btnCopy = New-Object Windows.Forms.Button
  $btnCopy.Text = 'Copy report'
  $btnCopy.Location = New-Object Drawing.Point(12, $btnRowY)
  $btnCopy.Size = New-Object Drawing.Size(130, 30)
  $btnCopy.Anchor = 'Bottom,Left'
  & $flat $btnCopy $false
  $tab2.Controls.Add($btnCopy)
  $btnCopy.Add_Click({ if ($mtext.Text) { [Windows.Forms.Clipboard]::SetText($mtext.Text) } })

  $loadMemory = {
    $mlv.Items.Clear()
    $dimms = @(Get-Dimms)
    $slots = 0
    foreach ($a in (Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue)) { $slots += $a.MemoryDevices }
    $cpu = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Name

    foreach ($d in $dimms) {
      $it = New-Object Windows.Forms.ListViewItem($d.Locator)
      [void]$it.SubItems.Add("$($d.GB) GB")
      [void]$it.SubItems.Add($d.Type)
      [void]$it.SubItems.Add("$($d.Rated) MT/s")
      [void]$it.SubItems.Add("$($d.Running) MT/s")
      [void]$it.SubItems.Add($(if ($d.CL) { "CL$($d.CL)" + $(if ($d.tRCD) { "-$($d.tRCD)-$($d.tRP)" } else { '' }) } else { '?' }))
      [void]$it.SubItems.Add("$($d.Vendor) $($d.Part)")
      [void]$mlv.Items.Add($it)
    }
    $head = "{0} stick(s) in {1} slot(s)   CPU: {2}" -f $dimms.Count, $slots, "$cpu".Trim()
    $mtext.Text = ($head, '', ((Get-MemoryNotes $dimms $slots $cpu) -join "`r`n")) -join "`r`n"
    if ($fitList) { & $fitList $mlv $mtextCard 0.4 }
  }
  & $loadMemory

  # ---- Motherboard tab ----
  $blv = New-Object Windows.Forms.ListView
  $blv.View = 'Details'; $blv.FullRowSelect = $true
  $blv.Location = New-Object Drawing.Point(12, 12)
  $blv.Size = New-Object Drawing.Size($ctlW, 190)
  $blv.Anchor = 'Top,Left,Right'
  $blv.BorderStyle = 'FixedSingle'
  $blv.BackColor = $card
  foreach ($c in @(@('Part', 76), @('Device', 220), @('Provider', 140), @('Version', 110), @('Date', 70), @('Note', 150))) {
    [void]$blv.Columns.Add($c[0], $c[1])
  }
  $tab3.Controls.Add($blv)

  $btext = New-Object Windows.Forms.TextBox
  $btext.Multiline = $true; $btext.ReadOnly = $true; $btext.ScrollBars = 'None'
  $btext.BackColor = $card
  $btext.Font = New-Object Drawing.Font('Consolas', 9)
  $btext.Location = New-Object Drawing.Point(12, 212)
  $btext.Size = New-Object Drawing.Size($ctlW, ($btnRowY - 222))
  $btext.Anchor = 'Top,Left,Right,Bottom'
  $btext.BorderStyle = 'FixedSingle'
  $tab3.Controls.Add($btext)

  $btnBoard = New-Object Windows.Forms.Button
  $btnBoard.Text = 'Open support page'
  $btnBoard.Location = New-Object Drawing.Point(12, $btnRowY)
  $btnBoard.Size = New-Object Drawing.Size(160, 30)
  $btnBoard.Anchor = 'Bottom,Left'
  & $flat $btnBoard $false
  $tab3.Controls.Add($btnBoard)
  $btnBoard.Add_Click({
    $b = Get-BoardInfo
    $q = [Uri]::EscapeDataString(("{0} {1} bios driver download" -f $b.Vendor, $b.Model))
    Start-Process "https://www.google.com/search?q=$q"
  })

  $loadBoard = {
    $blv.Items.Clear()
    foreach ($d in @(Get-DriverInfo)) {
      $it = New-Object Windows.Forms.ListViewItem($d.Category)
      [void]$it.SubItems.Add($d.Device)
      [void]$it.SubItems.Add($d.Provider)
      [void]$it.SubItems.Add([string]$d.Version)
      [void]$it.SubItems.Add($(if ($d.Date) { '{0:yyyy-MM}' -f $d.Date } else { '-' }))
      [void]$it.SubItems.Add($d.Note)
      [void]$blv.Items.Add($it)
    }
    if ($fitList) { & $fitList $blv $btextCard 0.5 }
    $btext.Text = ((Get-BiosNotes (Get-BoardInfo)) -join "`r`n") + "`r`n`r`n" +
      'Drivers: Windows Update carries chipset, network and audio drivers, but the vendor page is usually newer. Graphics drivers come from NVIDIA or AMD directly.'
  }

  # this tab costs about a second to build, so only do it when it is opened
  $script:boardLoaded = $false
  $script:netLoaded = $false

  # ---- Network tab ----
  $nlv = New-Object Windows.Forms.ListView
  $nlv.View = 'Details'; $nlv.CheckBoxes = $true; $nlv.FullRowSelect = $true; $nlv.HideSelection = $false
  $nlv.Location = New-Object Drawing.Point(12, 12)
  $nlv.Size = New-Object Drawing.Size($ctlW, 190)
  $nlv.Anchor = 'Top,Left,Right'
  $nlv.BorderStyle = 'FixedSingle'
  $nlv.BackColor = $card
  foreach ($c in @(@('Adapter', 120), @('Setting', 260), @('Now', 110), @('Change to', 100), @('Group', 170))) {
    [void]$nlv.Columns.Add($c[0], $c[1])
  }
  $tab4.Controls.Add($nlv)

  $ntext = New-Object Windows.Forms.TextBox
  $ntext.Multiline = $true; $ntext.ReadOnly = $true; $ntext.ScrollBars = 'None'
  $ntext.BackColor = $card
  $ntext.Font = New-Object Drawing.Font('Consolas', 9)
  $ntext.Location = New-Object Drawing.Point(12, 212)
  $ntext.Size = New-Object Drawing.Size($ctlW, ($btnRowY - 222))
  $ntext.Anchor = 'Top,Left,Right,Bottom'
  $ntext.BorderStyle = 'FixedSingle'
  $tab4.Controls.Add($ntext)

  $btnNet = New-Object Windows.Forms.Button
  $btnNet.Text = 'Apply selected'
  $btnNet.Location = New-Object Drawing.Point(12, $btnRowY)
  $btnNet.Size = New-Object Drawing.Size(130, 30)
  $btnNet.Anchor = 'Bottom,Left'
  & $flat $btnNet $true
  $tab4.Controls.Add($btnNet)

  $loadNet = {
    $nlv.Items.Clear()
    $netRows = @(Get-NetFindings)
    foreach ($r in $netRows) {
      $it = New-Object Windows.Forms.ListViewItem($r.Adapter)
      [void]$it.SubItems.Add($r.Setting)
      [void]$it.SubItems.Add($r.Current)
      [void]$it.SubItems.Add($r.Target)
      [void]$it.SubItems.Add($r.Group)
      $it.Tag = $r
      [void]$nlv.Items.Add($it)
    }
    # an empty grid is just dead space - drop it and let the report fill the pane
    $nlv.Visible = ($nlv.Items.Count -gt 0)
    if ($bars -and $bars[$nlv]) { $bars[$nlv].Visible = $nlv.Visible }
    $btnNet.Visible = ($nlv.Items.Count -gt 0)
    if ($nlv.Visible) {
      & $fitList $nlv $ntextCard 0.4
    } else {
      $ntextCard.Top = & $sc 12
      $ntextCard.Height = $tab4.ClientSize.Height - (& $sc 64)
    }

    $head = if ($nlv.Items.Count -eq 0) {
      'Nothing to change - every power saving and latency setting this tool checks is already off.'
    } else {
      $parts = foreach ($g in 'Repair', 'Power saving', 'Latency (optional)') {
        $c = @($netRows | Where-Object { $_.Group -eq $g }).Count
        if ($c) { "{0} {1}" -f $c, $g.ToLower() }
      }
      "Found: {0}. Power saving is worth turning off on a desktop; latency options trade CPU time for response, so test them. Tick and press Apply.{1}" -f ($parts -join ', '),
        $(if (Test-Admin) { '' } else { '  Needs administrator - use the button on the first tab.' })
    }
    $ntext.Text = $head + "`r`n`r`n" + ((Get-NetNotes) -join "`r`n")
  }

  $nlv.Add_ItemSelectionChanged({
    if ($nlv.SelectedItems.Count -gt 0) {
      $break = $ntext.Text.IndexOf("`r`n`r`n")
      $rest = $(if ($break -ge 0) { $ntext.Text.Substring($break + 4) } else { $ntext.Text })
      $ntext.Text = $nlv.SelectedItems[0].Tag.Why + "`r`n`r`n" + $rest
    }
  })

  $btnNet.Add_Click({
    $items = @($nlv.CheckedItems)
    if ($items.Count -eq 0) {
      [void](& $dialog 'Tick at least one row first.' 'TsakasOptimizer' 'OK')
      return
    }
    $names = ($items | ForEach-Object { "{0}: {1}" -f $_.Tag.Adapter, $_.Tag.Setting }) -join "`r`n"
    $ans = & $dialog "Apply these $($items.Count) change(s)?`r`n`r`n$names`r`n`r`nThe adapter resets, so the connection drops for a second or two." 'TsakasOptimizer' 'YesNo'
    if ($ans -ne 'Yes') { return }
    $done = 0; $errs = @()
    foreach ($it in $items) {
      try { Invoke-NetFix $it.Tag; $done++ }
      catch { $errs += "{0}: {1}" -f $it.Tag.Setting, $_.Exception.Message }
    }
    & $loadNet
    $ntext.Text = ("Changed {0} setting(s).{1}" -f $done, $(if ($errs) { '  Failed: ' + ($errs -join ' | ') } else { '  Undo them with the Undo button on the first tab.' })) +
      "`r`n`r`n" + $ntext.Text
  })

  # ---- App Optimizer ----
  $alv = New-Object Windows.Forms.ListView
  $alv.View = 'Details'; $alv.CheckBoxes = $true; $alv.FullRowSelect = $true; $alv.HideSelection = $false
  $alv.Location = New-Object Drawing.Point(12, 12)
  $alv.Size = New-Object Drawing.Size($ctlW, 260)
  $alv.Anchor = 'Top,Left,Right'
  foreach ($c in @(@('App', 100), @('Action', 100), @('Current state', 180), @('Result', 120), @('What it does', 300))) {
    [void]$alv.Columns.Add($c[0], $c[1])
  }
  $tab5.Controls.Add($alv)

  $atext = New-Object Windows.Forms.TextBox
  $atext.Multiline = $true; $atext.ReadOnly = $true; $atext.ScrollBars = 'None'
  $atext.Location = New-Object Drawing.Point(12, 282)
  $atext.Size = New-Object Drawing.Size($ctlW, ($btnRowY - 292))
  $atext.Anchor = 'Top,Left,Right,Bottom'
  $atext.Text = 'Select a row to see why it is listed.'
  $tab5.Controls.Add($atext)

  $btnApps = New-Object Windows.Forms.Button
  $btnApps.Text = 'Apply selected'
  $btnApps.Location = New-Object Drawing.Point(12, $btnRowY)
  $btnApps.Size = New-Object Drawing.Size(130, 30)
  $btnApps.Anchor = 'Bottom,Left'
  & $flat $btnApps $true
  $tab5.Controls.Add($btnApps)

  $loadApps = {
    $alv.Items.Clear()
    foreach ($r in @(Get-AppFindings)) {
      $it = New-Object Windows.Forms.ListViewItem($r.App)
      [void]$it.SubItems.Add($r.Action)
      [void]$it.SubItems.Add($r.Status)
      [void]$it.SubItems.Add($r.Target)
      [void]$it.SubItems.Add($r.Effect)
      $it.Tag = $r
      [void]$alv.Items.Add($it)
    }
    if ($fitList) { & $fitList $alv $atextCard 0.45 }
    if ($alv.Items.Count -eq 0) {
      $atext.Text = 'Discord and Spotify have no startup, running-process, or rebuildable-cache actions to offer right now.'
    } else {
      $atext.Text = 'Select a row to see why it is listed. Cache cleanup frees disk space; it is not a permanent speed boost.'
    }
  }

  $alv.Add_ItemSelectionChanged({
    if ($alv.SelectedItems.Count -gt 0) {
      $r = $alv.SelectedItems[0].Tag
      $atext.Text = "$($r.Effect)`r`n`r`n$($r.Why)"
    }
  })

  $btnApps.Add_Click({
    $items = @($alv.CheckedItems)
    if ($items.Count -eq 0) {
      [void](& $dialog 'Tick at least one row first.' 'TsakasOptimizer' 'OK')
      return
    }
    $names = ($items | ForEach-Object { "$($_.Tag.App): $($_.Tag.Action)" }) -join "`r`n"
    $ans = & $dialog "Apply these changes?`r`n`r`n$names" 'TsakasOptimizer' 'YesNo'
    if ($ans -ne 'Yes') { return }
    $done = 0; $errs = @()
    foreach ($it in $items) {
      try { Invoke-AppAction $it.Tag; $done++ }
      catch { $errs += "$($it.Tag.App) $($it.Tag.Action): $($_.Exception.Message)" }
    }
    & $loadApps
    $atext.Text = "Applied $done action(s).$(if ($errs) { "`r`n`r`nFailed:`r`n$($errs -join "`r`n")" } else { '' })"
  })

  $script:appLoaded = $false

  # ---- every list and text pane becomes a rounded white card ----
  $rowHeight = New-Object Windows.Forms.ImageList
  $rowHeight.ImageSize = New-Object Drawing.Size(1, (& $sc 28))
  foreach ($l in @($lv, $mlv, $blv, $nlv, $alv)) {
    $l.SmallImageList = $rowHeight
    $l.BorderStyle = 'None'
    $l.HeaderStyle = 'Nonclickable'
    $l.Font = New-Object Drawing.Font($family, 10)
    $l.BackColor = $card
    $l.ForeColor = $ink
  }
  # the reports are prose, so a proportional face reads far better than Consolas
  foreach ($t in @($details, $mtext, $btext, $ntext, $atext)) {
    $t.BackColor = $card
    $t.ForeColor = $ink
    $t.Font = New-Object Drawing.Font($family, 10)
  }
  $details.ForeColor = $muted
  $detailsCard = Add-PaddedCard $details 10 $line 8 $card
  $mtextCard   = Add-PaddedCard $mtext   10 $line 14 $card
  $btextCard   = Add-PaddedCard $btext   10 $line 14 $card
  $ntextCard   = Add-PaddedCard $ntext   10 $line 14 $card
  $atextCard   = Add-PaddedCard $atext   10 $line 14 $card
  foreach ($c in @($lv, $mlv, $blv, $nlv, $alv)) {
    Set-Rounded $c 10
    Add-Hairline $c $line 10
  }

  $headerFont = New-Object Drawing.Font($small, 9)
  $drawHeader = {
    param($s, $e)
    $g = $e.Graphics
    $b = New-Object Drawing.SolidBrush($card)
    $g.FillRectangle($b, $e.Bounds); $b.Dispose()
    $pen = New-Object Drawing.Pen($line, 1)
    $g.DrawLine($pen, $e.Bounds.Left, ($e.Bounds.Bottom - 1), $e.Bounds.Right, ($e.Bounds.Bottom - 1)); $pen.Dispose()
    $r = New-Object Drawing.Rectangle(($e.Bounds.X + (& $sc 8)), $e.Bounds.Y, [Math]::Max(0, $e.Bounds.Width - (& $sc 12)), $e.Bounds.Height)
    [Windows.Forms.TextRenderer]::DrawText($g, $e.Header.Text, $headerFont, $r, $muted,
      [Windows.Forms.TextFormatFlags]'Left, VerticalCenter, SingleLine, EndEllipsis')
  }.GetNewClosure()
  # the native checkbox stays white on a dark row; a state image list replaces
  # both glyphs, which is the only hook WinForms gives for them
  $checkImages = New-Object Windows.Forms.ImageList
  $cbSize = & $sc 16
  $checkImages.ImageSize = New-Object Drawing.Size($cbSize, $cbSize)
  $checkImages.ColorDepth = 'Depth32Bit'
  foreach ($on in @($false, $true)) {
    $bmp = New-Object Drawing.Bitmap($cbSize, $cbSize)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.ScaleTransform($dpiScale, $dpiScale)
    if ($on) {
      $b = New-Object Drawing.SolidBrush($accentFill)
      $g.FillRectangle($b, 2, 2, 12, 12)
      $b.Dispose()
      $pen = New-Object Drawing.Pen($white, 1.7)
      $g.DrawLines($pen, @(
        (New-Object Drawing.PointF(4.5, 8.2)),
        (New-Object Drawing.PointF(7, 10.6)),
        (New-Object Drawing.PointF(11.5, 5.4))))
      $pen.Dispose()
    } else {
      $pen = New-Object Drawing.Pen($muted, 1)
      $g.DrawRectangle($pen, 2, 2, 11, 11)
      $pen.Dispose()
    }
    $g.Dispose()
    $checkImages.Images.Add($bmp)
  }

  # the last column takes whatever width is left
  $fillLast = {
    param($s, $e)
    $n = $s.Columns.Count
    if ($n -eq 0) { return }
    $used = 0
    for ($i = 0; $i -lt $n - 1; $i++) { $used += $s.Columns[$i].Width }
    # exactly to the edge: any gap is header the owner-draw never reaches, and
    # the system paints that strip white
    $room = $s.ClientSize.Width - $used
    $s.Columns[$n - 1].Width = [Math]::Max(60, $room)
  }
  foreach ($l in @($lv, $mlv, $blv, $nlv, $alv)) {
    foreach ($col in $l.Columns) { $col.Width = & $sc $col.Width }
    $l.OwnerDraw = $true
    if ($l.CheckBoxes) { $l.StateImageList = $checkImages }
    $l.Add_DrawColumnHeader($drawHeader)
    $l.Add_DrawItem({ param($s, $e) $e.DrawDefault = $true })
    $l.Add_DrawSubItem({ param($s, $e) $e.DrawDefault = $true })
    $l.Add_Resize($fillLast)
    & $fillLast $l $null
  }

  # Windows 11 touches: Explorer-style list rows, and a title bar the same colour
  # as the window. Both need a couple of Win32 calls; if compiling them is blocked
  # (locked-down PCs), the app just keeps the plain look.
  try {
    if (-not ('TsakasNative' -as [type])) {
      Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class TsakasNative {
  [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
  public static extern int SetWindowTheme(IntPtr hWnd, string appName, string idList);
  [DllImport("dwmapi.dll")]
  public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
  // undocumented, but the only way to get dark checkboxes and scrollbars in Win32 controls
  [DllImport("uxtheme.dll", EntryPoint = "#135", CharSet = CharSet.Unicode)]
  public static extern int SetPreferredAppMode(int mode);
  [DllImport("uxtheme.dll", EntryPoint = "#104")]
  public static extern void RefreshImmersiveColorPolicyState();
  [DllImport("user32.dll", CharSet = CharSet.Auto)]
  public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")]
  public static extern bool ShowScrollBar(IntPtr hWnd, int bar, bool show);
}
'@
    }
    # 2 = force dark; this is what actually darkens checkboxes and scrollbars
    try { [void][TsakasNative]::SetPreferredAppMode(2); [TsakasNative]::RefreshImmersiveColorPolicyState() } catch { }
    foreach ($l in @($lv, $mlv, $blv, $nlv, $alv)) {
      [void][TsakasNative]::SetWindowTheme($l.Handle, 'DarkMode_Explorer', $null)
      # the header is its own window, and keeps a light background unless themed too
      $hdr = [TsakasNative]::SendMessage($l.Handle, 0x101F, [IntPtr]::Zero, [IntPtr]::Zero)   # LVM_GETHEADER
      if ($hdr -ne [IntPtr]::Zero) { [void][TsakasNative]::SetWindowTheme($hdr, 'DarkMode_ItemsView', $null) }
    }
    $colorRef = { param($c) [int]$c.R -bor ([int]$c.G -shl 8) -bor ([int]$c.B -shl 16) }
    $caption = & $colorRef $panel
    $captionText = & $colorRef $ink
    $round = 2
    $dark = 1
    # 20 dark title bar (so the window buttons invert), 35 caption colour,
    # 36 caption text, 33 corner preference - Windows 11 only, ignored elsewhere
    [void][TsakasNative]::DwmSetWindowAttribute($form.Handle, 20, [ref]$dark, 4)
    [void][TsakasNative]::DwmSetWindowAttribute($form.Handle, 35, [ref]$caption, 4)
    [void][TsakasNative]::DwmSetWindowAttribute($form.Handle, 36, [ref]$captionText, 4)
    [void][TsakasNative]::DwmSetWindowAttribute($form.Handle, 33, [ref]$round, 4)
  } catch { }

  # slim scrollbars for every list and report pane
  $barTrack = $card
  $barThumb = [Drawing.Color]::FromArgb(125, 125, 133)
  $barHot   = [Drawing.Color]::FromArgb(168, 168, 178)
  # A list sized to its rows needs no scrollbar at all. It only grows to a share
  # of the page, so a long list still scrolls rather than pushing the report out.
  $fitList = {
    param($list, $report, $maxShare)
    $rowH = $(if ($list.Items.Count -gt 0) { $list.Items[0].Bounds.Height } else { 0 })
    if ($rowH -le 0) { $rowH = $list.Font.Height + 8 }
    $needed = (& $sc 40) + ($list.Items.Count * $rowH)
    $ceiling = [int]($list.Parent.ClientSize.Height * $maxShare)
    $list.Height = [Math]::Max((& $sc 90), [Math]::Min($needed, $ceiling))
    if ($bars -and $bars[$list]) { $bars[$list].Height = $list.Height - (& $sc 4) }
    if ($report) {
      $report.Top = $list.Bottom + (& $sc 22)
      $report.Height = [Math]::Max((& $sc 90), ($list.Parent.ClientSize.Height - (& $sc 52) - $report.Top))
    }
  }

  $bars = @{}
  foreach ($c in @($lv, $mlv, $blv, $nlv, $alv, $mtext, $btext, $ntext, $atext)) {
    $bars[$c] = Add-SlimScrollbar $c $barTrack $barThumb $barHot $dpiScale
  }
  & $fitList $mlv $mtextCard 0.4        # memory loaded before the bars existed
  $barSyncs = @($bars.Values | ForEach-Object { $_.Sync })
  foreach ($l in @($lv, $mlv, $blv, $nlv, $alv)) { & $fillLast $l $null }
  $barTimer = New-Object Windows.Forms.Timer
  $barTimer.Interval = 120
  $barTimer.Add_Tick({ foreach ($sync in $barSyncs) { & $sync } }.GetNewClosure())
  $barTimer.Start()
  $form.Add_Deactivate({ $barTimer.Stop() }.GetNewClosure())
  $form.Add_Activated({ $barTimer.Start() }.GetNewClosure())

  # everything above is laid out at 100%; this is where it becomes real pixels
  if ($dpiScale -ne 1) { $form.Scale((New-Object Drawing.SizeF($dpiScale, $dpiScale))) }
  foreach ($l in @($lv, $mlv, $blv, $nlv, $alv)) { & $fillLast $l $null }

  & $selectSection 0

  # bottom-right of the tab page, once the real sizes exist
  $form.Add_Shown({
    $btnElev.Left = $tab1.ClientSize.Width - $btnElev.Width - (& $sc 12)
    $btnElev.Top  = $btnApply.Top
  }.GetNewClosure())

  [void]$form.ShowDialog()
}

# --- self test ---------------------------------------------------------------
function Invoke-SelfTest {
  $checks = @(
    @{N = 'AnyDesk is recognised';            R = ((Get-Suggestion 'AnyDesk' $null) -ne $null)}
    @{N = 'AnyDesk service goes to Manual';   R = ((Get-Suggestion 'AnyDesk' $null).A -eq 'Manual')}
    @{N = 'Discord is a kill, not a service'; R = ((Get-Suggestion 'Discord' $null).A -eq 'Kill')}
    @{N = 'unknown process is left alone';    R = ((Get-Suggestion 'some-random-app' $null) -eq $null)}
    @{N = 'lsass is protected';               R = (Test-Match 'lsass' $Protected)}
    @{N = 'svchost is protected';             R = (Test-Match 'svchost' $Protected)}
    @{N = 'Defender service is protected';    R = (Test-Match 'WinDefend' $ProtectedServices)}
    @{N = 'AnyDesk is not protected';         R = (-not (Test-Match 'AnyDesk' $Protected))}
    @{N = 'services match on display name';   R = ((Get-Suggestion 'gupdate' 'Google Update Service (gupdate)') -ne $null)}
    @{N = 'scan returns objects, not errors'; R = ((@(Get-Findings) | Where-Object { $_ -isnot [pscustomobject] }).Count -eq 0)}
  )

  # fake sticks, so these do not depend on this PC
  $fake = {
    param($ch, $slot, $rated, $run, $part)
    [pscustomobject]@{ Channel=$ch; Slot=$slot; Locator="CHANNEL $ch / DIMM $($slot-1)"; GB=16; Type='DDR5'
      Rated=$rated; Running=$run; Vendor='X'; Part=$part; CL=30; tRCD=38; tRP=38 }
  }
  $good   = @((& $fake 'A' 2 6000 6000 'F5-6000J3038F16G'), (& $fake 'B' 2 6000 6000 'F5-6000J3038F16G'))
  $noExpo = @((& $fake 'A' 2 6000 4800 'F5-6000J3038F16G'), (& $fake 'B' 2 6000 4800 'F5-6000J3038F16G'))
  $slot13 = @((& $fake 'A' 1 6000 6000 'F5-6000J3038F16G'), (& $fake 'B' 1 6000 6000 'F5-6000J3038F16G'))
  $oneCh  = @((& $fake 'A' 1 6000 6000 'F5-6000J3038F16G'), (& $fake 'A' 2 6000 6000 'F5-6000J3038F16G'))
  $cpu    = 'AMD Ryzen 7 7800X3D 8-Core Processor'
  $checks += @(
    @{N = 'slot parse: DIMM 1 is the 2nd slot';   R = ((Get-DimmSlotIndex 'DIMM 1') -eq 2)}
    @{N = 'slot parse: DIMM_A1 is the 1st slot';  R = ((Get-DimmSlotIndex 'DIMM_A1') -eq 1)}
    @{N = 'channel parse from bank label';        R = ((Get-DimmChannel 'P0 CHANNEL B' 'DIMM 1') -eq 'B')}
    @{N = 'EXPO off is detected';                 R = ((Get-MemoryNotes $noExpo 4 $cpu) -join "`n") -match 'EXPO/XMP is OFF'}
    @{N = 'EXPO on is not flagged';               R = -not (((Get-MemoryNotes $good 4 $cpu) -join "`n") -match 'is OFF')}
    @{N = 'correct A2/B2 placement passes';       R = ((Get-MemoryNotes $good 4 $cpu) -join "`n") -match 'correct placement'}
    @{N = 'sticks in A1/B1 are flagged';          R = ((Get-MemoryNotes $slot13 4 $cpu) -join "`n") -match 'in A1/B1'}
    @{N = 'both sticks one channel is flagged';   R = ((Get-MemoryNotes $oneCh 4 $cpu) -join "`n") -match 'single channel, half'}
    @{N = 'AM5 target advice appears';            R = ((Get-MemoryNotes $good 4 $cpu) -join "`n") -match 'DDR5-6000 CL30'}
    # behaviour scoring
    @{N = 'background autostart is flagged';      R = ((Get-ProcessGuess ([pscustomobject]@{Name='Overwolf';HasWindow=$false;RamMB=190;Company='Overwolf LTD';AutoStart=$true;BootMinutes=0.3})).Score -ge 5)}
    @{N = 'an app you have open is not flagged';  R = ((Get-ProcessGuess ([pscustomobject]@{Name='krita';HasWindow=$true;RamMB=900;Company='KDE';AutoStart=$false;BootMinutes=40})).Score -lt 5)}
    @{N = 'a quiet background tool is not flagged'; R = ((Get-ProcessGuess ([pscustomobject]@{Name='krita';HasWindow=$false;RamMB=40;Company='KDE';AutoStart=$false;BootMinutes=40})).Score -lt 5)}
    @{N = 'an updater helper is flagged';         R = ((Get-ProcessGuess ([pscustomobject]@{Name='KritaUpdater';HasWindow=$false;RamMB=8;Company='KDE';AutoStart=$false;BootMinutes=0.5})).Score -ge 5)}
    @{N = 'antivirus is never guessed about';     R = ((Get-ProcessGuess ([pscustomobject]@{Name='SomeAntivirusAgent';HasWindow=$false;RamMB=300;Company='X';AutoStart=$true;BootMinutes=0.1})).Score -eq 0)}
    @{N = 'third-party auto service is flagged';  R = ((Get-ServiceGuess ([pscustomobject]@{Name='HPPrintScanDoctorService';DisplayName='HP Print Scan Doctor Service';PathName='C:\Program Files\HP\x.exe';State='Running'})).Score -ge 4)}
    @{N = 'plain third-party service is not';     R = ((Get-ServiceGuess ([pscustomobject]@{Name='GameInputRedistService';DisplayName='GameInput Redist Service';PathName='C:\Program Files\x.exe';State='Running'})).Score -lt 4)}
    @{N = 'a Windows service is never guessed';   R = ((Get-ServiceGuess ([pscustomobject]@{Name='SomeUpdateSvc';DisplayName='Some Update Service';PathName="$env:SystemRoot\system32\svchost.exe";State='Running'})).Score -eq 0)}
    @{N = 'audio/driver services are left alone'; R = ((Get-ServiceGuess ([pscustomobject]@{Name='RtkAudUService';DisplayName='Realtek Audio Universal Service';PathName='C:\Program Files\Realtek\x.exe';State='Running'})).Score -eq 0)}
    @{N = 'autostart name prefix match works';    R = (Test-AutoStarts 'Overwolf' (New-Object System.Collections.Generic.HashSet[string] ([string[]]@('OverwolfLauncher'), [StringComparer]::OrdinalIgnoreCase)))}
    @{N = 'App Optimizer includes Discord';       R = ((@(Get-AppPlans | Where-Object Name -eq 'Discord')).Count -eq 1)}
    @{N = 'App Optimizer includes Spotify';       R = ((@(Get-AppPlans | Where-Object Name -eq 'Spotify')).Count -eq 1)}
    @{N = 'app scan runs without error';          R = ((@(Get-AppFindings)).Count -ge 0)}
    # network tab
    @{N = 'enabled green ethernet is flagged';    R = ((Get-NetOffValue 'Green Ethernet' 'Enabled' @('Disabled','Enabled')) -eq 'Disabled')}
    @{N = 'already-off setting is not flagged';   R = ($null -eq (Get-NetOffValue 'Green Ethernet' 'Disabled' @('Disabled','Enabled')))}
    @{N = 'EEE speed list is not a toggle';       R = ($null -eq (Get-NetOffValue 'EEE Max Support Speed' '2.5 Gbps Full Duplex' @('1.0 Gbps Full Duplex','2.5 Gbps Full Duplex')))}
    @{N = 'unrelated settings are left alone';    R = ($null -eq (Get-NetOffValue 'Jumbo Frame' 'Enabled' @('Disabled','Enabled')))}
    @{N = 'wake-on-lan is left alone';            R = ($null -eq (Get-NetOffValue 'Wake on Magic Packet' 'Enabled' @('Disabled','Enabled')))}
    @{N = 'Off counts as off';                    R = ($null -eq (Get-NetOffValue 'Power Saving Mode' 'Off' @('Off','On')))}
    @{N = 'interrupt moderation is offered';      R = ((Get-NetOffValue 'Interrupt Moderation' 'Enabled' @('Disabled','Enabled')) -eq 'Disabled')}
    @{N = 'moderation rate is not a toggle';      R = ($null -eq (Get-NetOffValue 'Interrupt Moderation Rate' 'Adaptive' @('Adaptive','Extreme','High','Low','Minimal','Off')))}
    @{N = 'checksum offload is offered';          R = ((Get-NetOffValue 'TCP Checksum Offload (IPv4)' 'Rx & Tx Enabled' @('Disabled','Tx Enabled','Rx Enabled','Rx & Tx Enabled')) -eq 'Disabled')}
    @{N = 'Intel checksum name matches too';      R = ((Get-NetOffValue 'TCP/UDP Checksum Offload (IPv6)' 'Rx & Tx Enabled' @('Disabled','Rx & Tx Enabled')) -eq 'Disabled')}
    @{N = 'large send offload is left alone';     R = ($null -eq (Get-NetOffValue 'Large Send Offload v2 (IPv4)' 'Enabled' @('Disabled','Enabled')))}
    @{N = 'segment coalescing is left alone';     R = ($null -eq (Get-NetOffValue 'Recv Segment Coalescing (IPv4)' 'Enabled' @('Disabled','Enabled')))}
    @{N = 'power saving sorts as power saving';   R = ((Get-NetGroup 'Green Ethernet') -eq 'Power saving')}
    @{N = 'checksum sorts as optional latency';   R = ((Get-NetGroup 'UDP Checksum Offload (IPv6)') -eq 'Latency (optional)')}
    @{N = 'network scan runs without error';      R = ((@(Get-NetFindings)).Count -ge 0)}
    # motherboard tab
    @{N = 'a 2 year old BIOS is flagged';         R = ((Get-BiosNotes ([pscustomobject]@{Vendor='X';Model='Y';Bios='F1';BiosDate=(Get-Date).AddMonths(-24);AgeMonths=24;Cpu='AMD Ryzen 7 7800X3D'}) ) -join "`n") -match 'over 18 months old'}
    @{N = 'a recent BIOS is not flagged';         R = ((Get-BiosNotes ([pscustomobject]@{Vendor='X';Model='Y';Bios='F1';BiosDate=(Get-Date).AddMonths(-2);AgeMonths=2;Cpu='AMD Ryzen 7 7800X3D'}) ) -join "`n") -match 'Recent BIOS'}
    @{N = 'AM5 gets the AGESA note';              R = ((Get-BiosNotes ([pscustomobject]@{Vendor='X';Model='Y';Bios='F1';BiosDate=(Get-Date).AddMonths(-2);AgeMonths=2;Cpu='AMD Ryzen 7 7800X3D'}) ) -join "`n") -match 'AGESA'}
    @{N = 'NVIDIA version is the published one';  R = ((Get-GpuVersion 'NVIDIA' '32.0.16.1088') -eq '610.88' -and (Get-GpuVersion 'NVIDIA' '31.0.15.3699') -eq '536.99')}
    @{N = 'Intel version drops the Windows part'; R = ((Get-GpuVersion 'Intel Corporation' '32.0.101.6314') -eq '101.6314')}
    @{N = 'AMD version is left untouched';        R = ((Get-GpuVersion 'Advanced Micro Devices, Inc.' '31.0.24033.1003') -eq '31.0.24033.1003')}
    @{N = 'generic Microsoft driver is called out'; R = ((Get-DriverNote 'Microsoft' (Get-Date) 'oem42.inf' 'PCI\VEN_8086') -match 'generic Windows driver')}
    @{N = 'an old driver is called out';          R = ((Get-DriverNote 'Realtek' ((Get-Date).AddYears(-4)) 'oem11.inf' '') -match 'over 3 years old')}
    @{N = 'a current vendor driver is silent';    R = ((Get-DriverNote 'Realtek' (Get-Date) 'oem11.inf' '') -eq '')}
    @{N = 'USB audio class driver is not nagged'; R = (((Get-DriverNote 'Microsoft' (Get-Date) 'usbaudio2.inf' 'USB\VID_1532&PID_0543') -notmatch 'vendor one usually') -and ((Get-DriverNote 'Microsoft' (Get-Date) 'usbaudio2.inf' 'USB\VID_1532') -match 'standard one'))}
    @{N = 'NVIDIA HDMI audio names NVIDIA';      R = ((Get-DriverNote 'Microsoft' (Get-Date) 'hdaudio.inf' 'HDAUDIO\FUNC_01&VEN_10DE&DEV_00A4') -match 'NVIDIA ships one')}
    @{N = 'AMD HDMI audio names AMD';            R = ((Get-DriverNote 'Microsoft' (Get-Date) 'hdaudio.inf' 'HDAUDIO\FUNC_01&VEN_1002&DEV_AAF0') -match 'AMD ships one')}
    @{N = 'the 2006 inbox date is not aged';     R = ((Get-DriverNote 'Microsoft' (Get-Date '2006-06-21') 'prnms009.inf' '') -notmatch 'years old')}
    @{N = 'a genuinely old driver still ages';   R = ((Get-DriverNote 'Realtek' (Get-Date '2006-06-20') 'oem11.inf' '') -match 'over 3 years old')}
    # the undo log: PowerShell 5.1 returns a JSON array as one object, which used
    # to nest the log on every save and leave undo seeing a single entry
    @{N = 'undo log keeps every entry';          R = (& {
        $f = Join-Path $env:TEMP ("undo-" + [guid]::NewGuid().ToString('N') + ".json")
        try {
          Add-UndoEntry ([pscustomobject]@{ Type = 'Service'; Name = 'A'; Previous = 'Auto' }) $f
          Add-UndoEntry ([pscustomobject]@{ Type = 'Service'; Name = 'B'; Previous = 'Auto' }) $f
          Add-UndoEntry ([pscustomobject]@{ Type = 'Service'; Name = 'C'; Previous = 'Auto' }) $f
          $read = Read-UndoLog $f
          (@($read).Count -eq 3) -and (@($read)[0].Name -eq 'A') -and (@($read)[2].Name -eq 'C')
        } finally { Remove-Item $f -ErrorAction SilentlyContinue }
      })}
    @{N = 'a log nested by old builds is read'; R = (& {
        $f = Join-Path $env:TEMP ("undo-" + [guid]::NewGuid().ToString('N') + ".json")
        try {
          '[{"value":[{"Type":"Service","Name":"A","Previous":"Auto"},{"Type":"Service","Name":"B","Previous":"Auto"}],"Count":2},{"Type":"Service","Name":"C","Previous":"Auto"}]' | Out-File $f -Encoding utf8
          @(Read-UndoLog $f).Count -eq 3
        } finally { Remove-Item $f -ErrorAction SilentlyContinue }
      })}
    @{N = 'a single-entry log still reads';      R = (& {
        $f = Join-Path $env:TEMP ("undo-" + [guid]::NewGuid().ToString('N') + ".json")
        try {
          '{"Type":"Service","Name":"Spooler","Previous":"Auto"}' | Out-File $f -Encoding utf8
          @(Read-UndoLog $f).Count -eq 1
        } finally { Remove-Item $f -ErrorAction SilentlyContinue }
      })}
    @{N = 'AM5 desktop chip is detected';        R = ((Test-Am5 'AMD Ryzen 7 7800X3D 8-Core Processor') -and (Test-Am5 'AMD Ryzen 5 8600G w/ Radeon Graphics') -and (Test-Am5 'AMD Ryzen 9 9950X 16-Core'))}
    @{N = 'mobile Ryzen is not called AM5';      R = (-not (Test-Am5 'AMD Ryzen 7 7735HS with Radeon') -and -not (Test-Am5 'AMD Ryzen 9 7945HX'))}
    @{N = 'AM4 and Intel are not called AM5';    R = (-not (Test-Am5 'AMD Ryzen 5 5600X 6-Core') -and -not (Test-Am5 'Intel Core i9-14900K'))}
    @{N = 'part number gives the rated speed';   R = ((Get-PartSpeed 'F5-6000J3038F16G') -eq 6000 -and (Get-PartSpeed 'CMK32GX5M2B6000C36') -eq 6000 -and (Get-PartSpeed 'KHX3200C16D4/8G') -eq 3200)}
    @{N = 'no rated speed when absent';          R = ((Get-PartSpeed 'NO-SUCH-PART') -eq 0)}
    @{N = 'chipset package reads or is absent';   R = ($null -eq (Get-ChipsetPackage) -or $null -ne (Get-ChipsetPackage).Version)}
    @{N = 'board info reads without error';       R = ((Get-BoardInfo) -ne $null)}
    @{N = 'G.Skill part number gives CL30-38';    R = (((Get-PartTimings 'F5-6000J3038F16G').CL -eq 30) -and ((Get-PartTimings 'F5-6000J3038F16G').tRCD -eq 38))}
    @{N = 'Corsair part number gives CL36';       R = ((Get-PartTimings 'CMK32GX5M2B6000C36').CL -eq 36)}
    @{N = 'unknown part number gives no CL';      R = ($null -eq (Get-PartTimings 'NO-SUCH-PART').CL)}
    @{N = 'reads this PC without error';          R = ((@(Get-Dimms)).Count -ge 0)}
  )
  $bad = 0
  foreach ($c in $checks) {
    if ($c.R) { Write-Host ("ok   " + $c.N) }
    else { Write-Host ("FAIL " + $c.N) -ForegroundColor Red; $bad++ }
  }
  if ($bad -eq 0) { Write-Host "`nself-test passed" -ForegroundColor Green }
  else { Write-Host "`n$bad check(s) failed" -ForegroundColor Red }
}

# --- main --------------------------------------------------------------------
if ($SelfTest) { Invoke-SelfTest; return }
if ($Undo)     { Invoke-Undo;     return }
if (-not $Console -and -not $Report) { Show-Gui; return }

Write-Host ''
Write-Host '  TsakasOptimizer - scanning processes and auto-start services...' -ForegroundColor Cyan
if (-not (Test-Admin)) { Write-Host '  (not running as Administrator - service changes will be skipped)' -ForegroundColor Yellow }
Write-Host ''

$findings = @(Get-Findings)
if ($findings.Count -eq 0) {
  Write-Host '  Nothing worth changing. Machine looks clean.' -ForegroundColor Green
  return
}

$freed = 0.0
$i = 0
foreach ($f in $findings) {
  $i++
  $ram = if ($f.RamMB -gt 0) { "{0} MB" -f $f.RamMB } else { "-" }
  $cnt = if ($f.Count -gt 1) { " x$($f.Count)" } else { "" }
  $st  = if ($f.Extra) { ", $($f.Extra)" } else { "" }
  $sug = if ($f.Action -eq 'Kill') { 'close it now' } else { 'set start type to Manual (starts on demand)' }

  $tag = if ($f.Confidence -eq 'Guess') { ', guess' } else { '' }
  Write-Host ("[{0}/{1}] {2}{3}  ({4}{5}, {6}{7})" -f $i, $findings.Count, $f.Label, $cnt, $f.Type, $tag, $ram, $st)
  Write-Host ("      " + $f.Why) -ForegroundColor DarkGray
  Write-Host ("      suggested: " + $sug) -ForegroundColor DarkCyan

  if ($Report) { Write-Host ''; continue }

  $ans = Read-Host '      apply? [y]es / [n]o (default) / [q]uit'
  if ($ans -match '^(q|quit)$') { break }
  if ($ans -match '^(y|yes)$') {
    try { $freed += Invoke-Finding $f }
    catch { Write-Host ("      failed: " + $_.Exception.Message) -ForegroundColor Red }
  }
  Write-Host ''
}

Write-Host ''
if ($Report) {
  Write-Host ("  {0} item(s) flagged. Run without -Report to act on them." -f $findings.Count) -ForegroundColor Cyan
} else {
  Write-Host ("  Done. Freed about {0} MB. Undo service changes with: .\TsakasOptimizer.ps1 -Undo" -f [math]::Round($freed,1)) -ForegroundColor Cyan
}
Write-Host ''
