#requires -Version 5.1
<#
  TsakasOptimizer.ps1 - scans running processes + auto-start services, flags the ones
  commonly safe to close or switch to Manual, and asks before touching anything.
  Service changes are logged so -Undo can put them back.
  #>
[CmdletBinding()]
param([switch]$Console, [switch]$Report, [switch]$Undo, [switch]$SelfTest)

$Version = '1.3.2'
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

function Add-UndoEntry($Entry) {
  $dir = Split-Path $UndoFile
  if (-not (Test-Path $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
  $log = @()
  if (Test-Path $UndoFile) { $log = @(Get-Content $UndoFile -Raw | ConvertFrom-Json) }
  $log += $Entry
  $log | ConvertTo-Json -Depth 4 | Out-File $UndoFile -Encoding utf8
}

function Invoke-Undo {
  if (-not (Test-Path $UndoFile)) { Write-Host 'Nothing to undo.'; return }
  if (-not (Test-Admin)) { Write-Host 'Run as Administrator to restore services.' -ForegroundColor Yellow; return }
  foreach ($e in @(Get-Content $UndoFile -Raw | ConvertFrom-Json)) {
    try {
      switch ($e.Type) {
        'AppStartup' {
          New-ItemProperty -Path $e.Key -Name $e.Name -Value $e.Data -PropertyType String -Force | Out-Null
        }
        'NetProperty' {
          Set-NetAdapterAdvancedProperty -Name $e.Adapter -DisplayName $e.Name -DisplayValue $e.Previous -ErrorAction Stop
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
    }
  }
  Remove-Item $UndoFile
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

  $am5  = $Cpu -match 'Ryzen\s+\d\s+[79]\d{3}'   # Ryzen 7 7800X3D / Ryzen 9 9950X = AM5
  $ddr5 = $Dimms[0].Type -eq 'DDR5'
  $rated = ($Dimms | Measure-Object Rated -Maximum).Maximum
  $run   = ($Dimms | Measure-Object Running -Minimum).Minimum

  # 1. EXPO / XMP
  if ($run -gt 0 -and $rated -gt 0 -and $run -lt ($rated - 50)) {
    [void]$n.Add(("[!] EXPO/XMP is OFF. The kit is rated {0} MT/s but is running at {1} MT/s - about {2}% of what you paid for." -f $rated, $run, [math]::Round(100 * $run / $rated)))
    [void]$n.Add('    Fix: BIOS -> EXPO (AMD) or XMP (Intel), pick Profile 1, save and reboot. Biggest single memory gain available to you.')
  } elseif ($ddr5 -and $run -le 5600 -and $rated -le 5600) {
    [void]$n.Add(("[i] Running at {0} MT/s, which is the JEDEC default. If the kit box says more (6000/6400), the EXPO profile is not being read - check BIOS." -f $run))
  } else {
    [void]$n.Add(("[ok] EXPO/XMP looks enabled: rated {0} MT/s, running {1} MT/s." -f $rated, $run))
  }

  # 2. slots
  $channels = @($Dimms | Group-Object Channel)
  if ($Dimms.Count -eq 2 -and $Slots -ge 4) {
    if ($channels.Count -lt 2) {
      [void]$n.Add(("[!] Both sticks are in the same channel ({0}) - you are running single channel and losing roughly half your memory bandwidth." -f $channels[0].Name))
      [void]$n.Add('    Fix: move one stick to the other channel (slots 2 and 4 counting from the CPU).')
    } elseif (($Dimms | Where-Object { $_.Slot -eq 2 }).Count -eq 2) {
      [void]$n.Add('[ok] Two sticks, dual channel, both in the second slot of their channel (A2/B2) - that is 99% the correct placement.')
    } elseif (($Dimms | Where-Object { $_.Slot -eq 1 }).Count -eq 2) {
      [void]$n.Add('[!] Both sticks look like they are in the FIRST slot of each channel (A1/B1).')
      [void]$n.Add('    Fix: move them to slots 2 and 4 (A2/B2, furthest from the CPU). Boards are wired for that pair; A1/B1 often will not hold EXPO speeds.')
    } else {
      [void]$n.Add(('[i] Slot layout could not be read confidently: ' + (($Dimms | ForEach-Object { $_.Locator }) -join ' | ') + '. Check the manual - 2 sticks belong in slots 2 and 4.'))
    }
  } elseif ($Dimms.Count -eq 1) {
    [void]$n.Add('[!] Only one stick: single channel. A second identical stick is the cheapest large gain for gaming and anything CPU-bound.')
  } elseif ($Dimms.Count -ge 4 -and $ddr5) {
    [void]$n.Add('[i] Four DDR5 sticks: the memory controller usually cannot hold 6000+ with all four slots filled. 5600 or lower here is normal, not a fault.')
  }

  # 3. mixed kit
  if (($Dimms | Select-Object -ExpandProperty Part -Unique).Count -gt 1 -or
      ($Dimms | Select-Object -ExpandProperty GB   -Unique).Count -gt 1) {
    [void]$n.Add('[!] The sticks are not identical. Mixed kits frequently fail to run their rated profile - if EXPO is unstable, this is the first suspect.')
  }

  # 4. platform target
  [void]$n.Add('')
  [void]$n.Add('--- PROCEED WITH CAUTION - everything below is BIOS tuning. Wrong values mean no boot (fixable with a CMOS clear), and an unstable profile can corrupt data. Change one thing at a time. ---')
  if ($am5 -and $ddr5) {
    [void]$n.Add('[i] AM5 sweet spot is DDR5-6000 CL30 with FCLK 2000 and UCLK=MEMCLK (1:1). Past ~6400 the controller drops to 2:1 and usually gets slower, not faster.')
  } elseif ($ddr5) {
    [void]$n.Add('[i] Intel DDR5 scales further than AMD: 6400-7200 is reasonable if the board and kit allow it.')
  } else {
    [void]$n.Add('[i] DDR4 target: 3600 CL16 on Ryzen (1:1 with FCLK 1800), 3600-4000 on Intel.')
  }

  # 5. timings
  $cl = ($Dimms | Where-Object { $_.CL } | Select-Object -First 1).CL
  if ($cl) {
    [void]$n.Add(("[i] Part number decodes to CL{0}{1} at {2} MT/s (this is the rated SPD profile, not necessarily what is loaded)." -f
      $cl, $(if ($Dimms[0].tRCD) { "-$($Dimms[0].tRCD)-$($Dimms[0].tRP)" } else { '' }), $rated))
    if ($ddr5 -and $rated -ge 6000 -and $cl -ge 30) {
      [void]$n.Add('    Tightening worth trying, one at a time: CL 30 -> 28, tRCD/tRP -> 36, tRAS -> 32, tRFC -> ~480ns (from the usual 560ns). VDD/VDDQ 1.35-1.40V.')
    } elseif ($ddr5) {
      [void]$n.Add('    Get the rated profile stable first; tightening below the rated CL is worth 1-3% at best.')
    } else {
      [void]$n.Add('    On DDR4 the big ones are tCL, tRCD/tRP and tRFC. Samsung B-die tightens a lot, Hynix/Micron much less.')
    }
    [void]$n.Add('    Realistic gain from tightening an already-correct EXPO profile: 1-3% in games, near zero elsewhere. Getting EXPO on at all is worth 10x that.')
  }

  [void]$n.Add('')
  [void]$n.Add('Note: Windows does not expose live memory timings - the values above come from the SPD/rated profile. Read the actual loaded timings in BIOS, in ZenTimings (AM5) or the CPU-Z SPD tab.')
  [void]$n.Add('Test any change with TestMem5 (anta777 config) or Karhu for at least an hour. If the PC will not boot, clear CMOS to get back to defaults.')
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

  $am5 = $Board.Cpu -match 'Ryzen\s+\d\s+[79]\d{3}'
  if ($Board.AgeMonths -lt 6) {
    [void]$n.Add('[ok] That BIOS is recent. Nothing to do unless you are chasing a specific bug.')
  } elseif ($Board.AgeMonths -lt 18) {
    [void]$n.Add('[i] A newer BIOS probably exists. Worth updating only if you have a reason: memory instability, a new CPU, or a fix listed in the changelog.')
  } else {
    [void]$n.Add('[!] This BIOS is over 18 months old. Vendors ship real fixes in that time - check the changelog on the support page.')
  }
  if ($am5) {
    [void]$n.Add('    On AM5 specifically, BIOS updates carry AGESA versions that fix memory training and EXPO stability. If your RAM is fussy, this is the first thing to try.')
  }
  [void]$n.Add('')
  [void]$n.Add('Windows cannot tell you which BIOS version is the newest - only the vendor page lists that. Use the button below, match your exact model, and compare against the version above.')
  [void]$n.Add('')
  [void]$n.Add('--- PROCEED WITH CAUTION - a failed BIOS flash can leave the board unbootable. Use the vendor tool (Q-Flash, M-Flash, EZ Flash), never flash on an unstable machine, and do not cut power during it. ---')
  return $n
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
    # chipset ships as one package, so report it as one line dated by its oldest piece
    if ($g.Cat -eq 'Chipset') {
      $oldest = $g.Rows | Sort-Object DriverDate | Select-Object -First 1
      [void]$rows.Add([pscustomobject]@{
        Category = 'Chipset'; Device = ("{0} chipset ({1} devices)" -f ($oldest.DriverProviderName -replace ',.*$', ''), $g.Rows.Count)
        Provider = $oldest.DriverProviderName; Version = $oldest.DriverVersion; Date = $oldest.DriverDate
        Note = (Get-DriverNote $oldest.DriverProviderName $oldest.DriverDate) })
      continue
    }
    foreach ($d in $g.Rows) {
      [void]$rows.Add([pscustomobject]@{
        Category = $g.Cat; Device = $d.DeviceName; Provider = $d.DriverProviderName
        Version = $d.DriverVersion; Date = $d.DriverDate; Note = (Get-DriverNote $d.DriverProviderName $d.DriverDate) })
    }
  }
  $rows
}

function Get-DriverNote([string]$Provider, $Date) {
  $notes = @()
  if ($Provider -like 'Microsoft*') { $notes += 'generic Windows driver - the vendor one usually adds features and fixes' }
  if ($Date) {
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

$NetWhy = @{
  'Energy-Efficient Ethernet' = 'Powers the link down between packets. Saves under a watt, and is a known cause of latency spikes and dropped links.'
  'Advanced EEE'              = 'Aggressive version of the same link power saving. Same trade, worse.'
  'Green Ethernet'            = 'Cuts transmit power based on cable length. Can cause renegotiation on marginal cables.'
  'Gigabit Lite'              = 'Runs the link in a lower-power mode. Can drop you to a slower speed.'
  'Power Saving Mode'         = 'Vendor power saving for the adapter. Trades latency for a trivial amount of power.'
  'Selective Suspend'         = 'Lets Windows suspend the adapter when idle. It wakes late, so the first packet after a pause is slow.'
}

# Returns the value to set it to, or $null when the property is not a simple
# on/off switch or is already off.
function Get-NetOffValue([string]$DisplayName, [string]$Current, $ValidValues) {
  if ($DisplayName -notmatch $NetPowerProps) { return $null }
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
      $why = $NetWhy[$p.DisplayName]
      if (-not $why) { $why = 'Adapter power saving. Turning it off keeps the link up and responsive.' }
      [void]$rows.Add([pscustomobject]@{
        Kind = 'Property'; Adapter = $a.Name; Setting = $p.DisplayName
        Current = $p.DisplayValue; Target = $off; Why = $why
      })
    }
    $pm = try { Get-NetAdapterPowerManagement -Name $a.Name -ErrorAction Stop } catch { $null }
    if ($pm -and $pm.AllowComputerToTurnOffDevice -eq 'Enabled') {
      [void]$rows.Add([pscustomobject]@{
        Kind = 'Power'; Adapter = $a.Name; Setting = 'Allow the computer to turn off this device'
        Current = 'Enabled'; Target = 'Disabled'
        Why = 'Windows may power the adapter down to save energy. This is the classic cause of "the internet drops after the PC has been idle".'
      })
    }
  }
  $rows
}

function Get-NetNotes {
  $n = New-Object System.Collections.ArrayList
  foreach ($a in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Not Present' })) {
    [void]$n.Add(("{0}: {1}, link {2}, {3}" -f $a.Name, $a.InterfaceDescription, $a.LinkSpeed, $a.Status))

    $speeds = (Get-NetAdapterAdvancedProperty -Name $a.Name -DisplayName 'Speed & Duplex' -ErrorAction SilentlyContinue).ValidDisplayValues
    if ($speeds -and ($speeds -match '2\.5 Gbps') -and $a.LinkSpeed -like '1 Gbps*') {
      [void]$n.Add('    [i] The adapter supports 2.5 Gbps but negotiated 1 Gbps. That is the switch or the cable, not a setting - you need a 2.5G port and cat5e or better.')
    }
    $pm = try { Get-NetAdapterPowerManagement -Name $a.Name -ErrorAction Stop } catch { $null }
    if (-not $pm) {
      [void]$n.Add('    [i] Windows could not read this adapter power settings (some Realtek drivers refuse). Check them by hand: Device Manager, the adapter, Power Management tab.')
    }
  }
  [void]$n.Add('')
  [void]$n.Add('Applying a change briefly resets the adapter, so the connection drops for a second or two. Do not do it mid-download, and never over a remote desktop session you cannot afford to lose.')
  [void]$n.Add('On a laptop running from battery, leave these alone - that is what they are for.')
  return $n
}

function Invoke-NetFix($Row) {
  if (-not (Test-Admin)) { throw 'needs Administrator' }
  if ($Row.Kind -eq 'Property') {
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

# Painted by hand: vertical gradient, a sheen over the top half, a defined edge.
# $Bg is whatever sits behind the button, so the rounded corners can be
# antialiased against it instead of clipped square by a region.
function Set-Glossy($Btn, $Top, $Bottom, $Border, $Fore, $Bg, [int]$Radius) {
  $Btn.FlatStyle = 'Flat'
  $Btn.FlatAppearance.BorderSize = 0
  $Btn.FlatAppearance.MouseOverBackColor = $Bg
  $Btn.FlatAppearance.MouseDownBackColor = $Bg
  $Btn.BackColor = $Bg
  $Btn.ForeColor = $Fore
  $Btn.UseVisualStyleBackColor = $false
  $Btn.Region = $null
  $state = New-Object psobject -Property @{ Hot = $false; Down = $false }

  $Btn.Add_MouseEnter({ $state.Hot = $true;  $Btn.Invalidate() }.GetNewClosure())
  $Btn.Add_MouseLeave({ $state.Hot = $false; $state.Down = $false; $Btn.Invalidate() }.GetNewClosure())
  $Btn.Add_MouseDown({ $state.Down = $true;  $Btn.Invalidate() }.GetNewClosure())
  $Btn.Add_MouseUp({   $state.Down = $false; $Btn.Invalidate() }.GetNewClosure())

  $Btn.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.Clear($Bg)
    if (-not $s.Enabled) { return }
    $g.SmoothingMode = 'AntiAlias'
    $rect = New-Object Drawing.Rectangle(0, 0, ($s.Width - 1), ($s.Height - 1))
    $path = New-RoundPath $rect $Radius

    $t = $Top; $b = $Bottom
    if ($state.Down)     { $t = Shift-Color $Top -18; $b = Shift-Color $Bottom -18 }
    elseif ($state.Hot)  { $t = Shift-Color $Top 10;  $b = Shift-Color $Bottom 10 }

    $fill = New-Object Drawing.Drawing2D.LinearGradientBrush($rect, $t, $b, 90)
    $g.FillPath($fill, $path)

    $saved = $g.Clip
    $g.SetClip($path)
    $half = New-Object Drawing.Rectangle(0, 0, ($s.Width - 1), [int](($s.Height - 1) / 2))
    if ($half.Height -gt 0) {
      $sheen = New-Object Drawing.Drawing2D.LinearGradientBrush($half,
        [Drawing.Color]::FromArgb(120, 255, 255, 255), [Drawing.Color]::FromArgb(18, 255, 255, 255), 90)
      $g.FillRectangle($sheen, $half)
      $sheen.Dispose()
    }
    $g.Clip = $saved

    $pen = New-Object Drawing.Pen($Border, 1)
    $g.DrawPath($pen, $path)

    $fmt = New-Object Drawing.StringFormat
    $fmt.LineAlignment = 'Center'
    $fmt.Alignment = $(if ($s.TextAlign -eq 'MiddleLeft') { 'Near' } else { 'Center' })
    $fmt.FormatFlags = 'NoWrap'
    $fmt.Trimming = 'EllipsisCharacter'
    $pad = $(if ($s.TextAlign -eq 'MiddleLeft') { 12 } else { 0 })
    $textRect = New-Object Drawing.RectangleF($pad, 0, ($s.Width - $pad), $s.Height)
    $brush = New-Object Drawing.SolidBrush($s.ForeColor)
    $g.DrawString($s.Text, $s.Font, $brush, $textRect, $fmt)

    $fill.Dispose(); $pen.Dispose(); $brush.Dispose(); $path.Dispose(); $fmt.Dispose(); $brush.Dispose()
  }.GetNewClosure())
}

# wraps a control in a padded white card and returns the card
function Add-PaddedCard($Ctrl, [int]$Radius, $LineColor, [int]$Pad) {
  $card = New-Object Windows.Forms.Panel
  $card.Location = $Ctrl.Location
  $card.Size = $Ctrl.Size
  $card.Anchor = $Ctrl.Anchor
  $card.BackColor = [Drawing.Color]::White
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
  $form.ClientSize = New-Object Drawing.Size(1040, 640)
  $form.MinimumSize = New-Object Drawing.Size(960, 620)
  $form.StartPosition = 'CenterScreen'

  $accent = [Drawing.Color]::FromArgb(0, 113, 227)
  $ink    = [Drawing.Color]::FromArgb(29, 29, 31)
  $muted  = [Drawing.Color]::FromArgb(110, 110, 115)
  $line   = [Drawing.Color]::FromArgb(210, 210, 215)
  $panel  = [Drawing.Color]::FromArgb(245, 245, 247)
  $white  = [Drawing.Color]::White
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

  # the ground everything sits on, so glossy corners can blend into it
  $btnEdge = [Drawing.Color]::FromArgb(188, 189, 196)
  $flat = {
    param($b, $primary)
    $b.Cursor = 'Hand'
    $b.Height = 34
    if ($primary) {
      $b.Font = New-Object Drawing.Font($semi, 10)
      Set-Glossy $b ([Drawing.Color]::FromArgb(64, 150, 240)) ([Drawing.Color]::FromArgb(0, 105, 214)) `
                 ([Drawing.Color]::FromArgb(0, 84, 173)) $white $panel 8
    } else {
      Set-Glossy $b $white ([Drawing.Color]::FromArgb(226, 227, 233)) $btnEdge $ink $panel 8
    }
  }

  # ---- sidebar ----
  $side = New-Object Windows.Forms.Panel
  $side.Location = New-Object Drawing.Point(0, 0)
  $side.Size = New-Object Drawing.Size(208, 592)
  $side.Anchor = 'Top,Left,Bottom'
  $side.BackColor = $white
  $sideLine = $line
  $side.Add_Paint({
    param($s, $e)
    $pen = New-Object Drawing.Pen($sideLine, 1)
    $e.Graphics.DrawLine($pen, $s.Width - 1, 0, $s.Width - 1, $s.Height)
    $pen.Dispose()
  }.GetNewClosure())
  $form.Controls.Add($side)

  $brand = New-Object Windows.Forms.Label
  $brand.Text = 'TsakasOptimizer'
  $brand.Font = New-Object Drawing.Font($display, 14)
  $brand.ForeColor = $ink
  $brand.AutoSize = $true
  $brand.Location = New-Object Drawing.Point(20, 26)
  $side.Controls.Add($brand)

  $verLabel = New-Object Windows.Forms.Label
  $verLabel.Text = "Version $Version"
  $verLabel.Font = New-Object Drawing.Font($small, 9)
  $verLabel.ForeColor = $muted
  $verLabel.AutoSize = $true
  $verLabel.Location = New-Object Drawing.Point(21, 52)
  $side.Controls.Add($verLabel)

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
    $pane.Location = New-Object Drawing.Point(208, 0)
    $pane.Size = New-Object Drawing.Size(832, 592)
    $pane.Anchor = 'Top,Left,Right,Bottom'
    $pane.BackColor = $panel
    $pane.Visible = ($i -eq 0)
    $form.Controls.Add($pane)

    $head = New-Object Windows.Forms.Label
    $head.Text = $sections[$i].Title
    $head.Font = New-Object Drawing.Font($display, 18)
    $head.ForeColor = $ink
    $head.AutoSize = $true
    $head.Location = New-Object Drawing.Point(12, 20)
    $pane.Controls.Add($head)

    $sub = New-Object Windows.Forms.Label
    $sub.Text = $sections[$i].Sub
    $sub.Font = New-Object Drawing.Font($family, 10)
    $sub.ForeColor = $muted
    $sub.AutoSize = $true
    $sub.Location = New-Object Drawing.Point(14, 50)
    $pane.Controls.Add($sub)

    $body = New-Object Windows.Forms.Panel
    $body.Location = New-Object Drawing.Point(0, 76)
    $body.Size = New-Object Drawing.Size(832, 504)
    $body.Anchor = 'Top,Left,Right,Bottom'
    $body.BackColor = $panel
    $pane.Controls.Add($body)

    $nav = New-Object Windows.Forms.Button
    $nav.Text = $sections[$i].Title
    $nav.TextAlign = 'MiddleLeft'
    $nav.Padding = New-Object Windows.Forms.Padding(10, 0, 0, 0)
    $nav.Size = New-Object Drawing.Size(176, 34)
    $nav.Location = New-Object Drawing.Point(16, (96 + $i * 40))
    $nav.FlatStyle = 'Flat'
    $nav.FlatAppearance.BorderSize = 0
    $nav.Cursor = 'Hand'
    $nav.Tag = $i
    Set-Rounded $nav 8
    $side.Controls.Add($nav)

    $panes  += $pane
    $navs   += $nav
    $bodies += $body
  }
  $tab1 = $bodies[0]
  $tab2 = $bodies[1]
  $tab3 = $bodies[2]
  $tab4 = $bodies[3]
  $tab5 = $bodies[4]

  $selectSection = {
    param($index)
    for ($k = 0; $k -lt $panes.Count; $k++) {
      $panes[$k].Visible = ($k -eq $index)
      if ($k -eq $index) {
        $navs[$k].BackColor = $accent
        $navs[$k].ForeColor = $white
        $navs[$k].Font = New-Object Drawing.Font($semi, 10)
      } else {
        $navs[$k].BackColor = $white
        $navs[$k].ForeColor = $ink
        $navs[$k].Font = New-Object Drawing.Font($family, 10)
      }
    }
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
  $lv.Size = New-Object Drawing.Size(800, 330)
  $lv.Anchor = 'Top,Left,Right,Bottom'
  $lv.BorderStyle = 'FixedSingle'
  $lv.BackColor = [Drawing.Color]::White
  [void]$lv.Columns.Add('App Name', 330)
  [void]$lv.Columns.Add('Type', 70)
  [void]$lv.Columns.Add('RAM', 90)
  [void]$lv.Columns.Add('Suggested', 290)
  $tab1.Controls.Add($lv)

  $details = New-Object Windows.Forms.TextBox
  $details.Multiline = $true; $details.ReadOnly = $true; $details.BackColor = 'Window'
  $details.Location = New-Object Drawing.Point(12, 352)
  $details.Size = New-Object Drawing.Size(800, 56)
  $details.Anchor = 'Left,Right,Bottom'
  $details.BorderStyle = 'FixedSingle'
  $details.ForeColor = $muted
  $details.Text = 'Scans the processes your CPU/PC runs. Suggests putting services on Manual instead of Automatic and closing unnessecary apps. Tick what you want changed, then press Apply.'
  $tab1.Controls.Add($details)

  $status = New-Object Windows.Forms.Label
  $status.Location = New-Object Drawing.Point(12, 418)
  $status.Size = New-Object Drawing.Size(800, 40)
  $status.Anchor = 'Left,Right,Bottom'
  $status.ForeColor = $muted
  $tab1.Controls.Add($status)

  $mkButton = {
    param($text, $x, $w)
    $b = New-Object Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object Drawing.Point($x, 462)
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
  $btnElev.Location = New-Object Drawing.Point(($form.ClientSize.Width - $btnElev.Width - 12), 462)

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
  $footer.Location = New-Object Drawing.Point(0, 592)
  $footer.Size = New-Object Drawing.Size(1040, 48)
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
      [void][Windows.Forms.MessageBox]::Show(
        "You launched this straight from GitHub, so you are already on the latest version ($Version).",
        'Up to date', 'OK', 'Information')
      return
    }
    $btnUpdate.Enabled = $false
    $form.Cursor = 'WaitCursor'
    try { $script:online = Get-OnlineRelease } finally { $form.Cursor = 'Default'; $btnUpdate.Enabled = $true }

    if (-not $script:online) {
      [void][Windows.Forms.MessageBox]::Show(
        "Could not reach $Repo on GitHub. Check your connection, or download the latest copy yourself.",
        'Update check failed', 'OK', 'Warning')
      return
    }
    if ([version]$script:online.Version -le [version]$Version) {
      $dot.Visible = $false
      [void][Windows.Forms.MessageBox]::Show("You are on the latest version ($Version).", 'Up to date', 'OK', 'Information')
      return
    }
    $ans = [Windows.Forms.MessageBox]::Show(
      "Version $($script:online.Version) is available (you have $Version).`r`n`r`nDownload it and restart TsakasOptimizer?",
      'Update available', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    try {
      Install-Update $script:online.Text
      Start-Process powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath)
      $form.Close()
    } catch {
      [void][Windows.Forms.MessageBox]::Show("Update failed: $($_.Exception.Message)", 'Update failed', 'OK', 'Error')
    }
  })

  $btnRefresh.Add_Click({ & $refresh })

  $btnApply.Add_Click({
    $items = @($lv.CheckedItems)
    if ($items.Count -eq 0) {
      [void][Windows.Forms.MessageBox]::Show('Tick at least one row first.', 'TsakasOptimizer')
      return
    }
    $names = ($items | ForEach-Object { $_.Tag.Label }) -join "`r`n"
    $ans = [Windows.Forms.MessageBox]::Show(
      "Apply to these $($items.Count) item(s)?`r`n`r`n$names", 'TsakasOptimizer', 'YesNo', 'Question')
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
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    $form.Close()
  })

  # ---- Memory tab ----
  $mlv = New-Object Windows.Forms.ListView
  $mlv.View = 'Details'; $mlv.FullRowSelect = $true
  $mlv.Location = New-Object Drawing.Point(12, 12)
  $mlv.Size = New-Object Drawing.Size(800, 130)
  $mlv.Anchor = 'Top,Left,Right'
  $mlv.BorderStyle = 'FixedSingle'
  $mlv.BackColor = [Drawing.Color]::White
  foreach ($c in @(@('Slot', 170), @('Size', 60), @('Type', 60), @('Rated', 80), @('Running', 80), @('Timings', 90), @('Part', 230))) {
    [void]$mlv.Columns.Add($c[0], $c[1])
  }
  $tab2.Controls.Add($mlv)

  $mtext = New-Object Windows.Forms.TextBox
  $mtext.Multiline = $true; $mtext.ReadOnly = $true; $mtext.ScrollBars = 'Vertical'
  $mtext.BackColor = 'Window'
  $mtext.Font = New-Object Drawing.Font('Consolas', 9)
  $mtext.Location = New-Object Drawing.Point(12, 152)
  $mtext.Size = New-Object Drawing.Size(800, 300)
  $mtext.Anchor = 'Top,Left,Right,Bottom'
  $mtext.BorderStyle = 'FixedSingle'
  $mtext.ForeColor = $ink
  $tab2.Controls.Add($mtext)

  $btnCopy = New-Object Windows.Forms.Button
  $btnCopy.Text = 'Copy report'
  $btnCopy.Location = New-Object Drawing.Point(12, 462)
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
    $head = "{0} stick(s) in {1} slot(s)   CPU: {2}" -f $dimms.Count, $slots, $cpu
    $mtext.Text = ($head, '', ((Get-MemoryNotes $dimms $slots $cpu) -join "`r`n")) -join "`r`n"
  }
  & $loadMemory

  # ---- Motherboard tab ----
  $blv = New-Object Windows.Forms.ListView
  $blv.View = 'Details'; $blv.FullRowSelect = $true
  $blv.Location = New-Object Drawing.Point(12, 12)
  $blv.Size = New-Object Drawing.Size(800, 190)
  $blv.Anchor = 'Top,Left,Right'
  $blv.BorderStyle = 'FixedSingle'
  $blv.BackColor = [Drawing.Color]::White
  foreach ($c in @(@('Part', 80), @('Device', 240), @('Provider', 150), @('Version', 110), @('Date', 80), @('Note', 270))) {
    [void]$blv.Columns.Add($c[0], $c[1])
  }
  $tab3.Controls.Add($blv)

  $btext = New-Object Windows.Forms.TextBox
  $btext.Multiline = $true; $btext.ReadOnly = $true; $btext.ScrollBars = 'Vertical'
  $btext.BackColor = 'Window'
  $btext.Font = New-Object Drawing.Font('Consolas', 9)
  $btext.Location = New-Object Drawing.Point(12, 212)
  $btext.Size = New-Object Drawing.Size(800, 240)
  $btext.Anchor = 'Top,Left,Right,Bottom'
  $btext.BorderStyle = 'FixedSingle'
  $tab3.Controls.Add($btext)

  $btnBoard = New-Object Windows.Forms.Button
  $btnBoard.Text = 'Open support page'
  $btnBoard.Location = New-Object Drawing.Point(12, 462)
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
  $nlv.Size = New-Object Drawing.Size(800, 190)
  $nlv.Anchor = 'Top,Left,Right'
  $nlv.BorderStyle = 'FixedSingle'
  $nlv.BackColor = [Drawing.Color]::White
  foreach ($c in @(@('Adapter', 120), @('Setting', 280), @('Now', 100), @('Change to', 100), @('', 180))) {
    [void]$nlv.Columns.Add($c[0], $c[1])
  }
  $tab4.Controls.Add($nlv)

  $ntext = New-Object Windows.Forms.TextBox
  $ntext.Multiline = $true; $ntext.ReadOnly = $true; $ntext.ScrollBars = 'Vertical'
  $ntext.BackColor = 'Window'
  $ntext.Font = New-Object Drawing.Font('Consolas', 9)
  $ntext.Location = New-Object Drawing.Point(12, 212)
  $ntext.Size = New-Object Drawing.Size(800, 240)
  $ntext.Anchor = 'Top,Left,Right,Bottom'
  $ntext.BorderStyle = 'FixedSingle'
  $tab4.Controls.Add($ntext)

  $btnNet = New-Object Windows.Forms.Button
  $btnNet.Text = 'Apply selected'
  $btnNet.Location = New-Object Drawing.Point(12, 462)
  $btnNet.Size = New-Object Drawing.Size(130, 30)
  $btnNet.Anchor = 'Bottom,Left'
  & $flat $btnNet $true
  $tab4.Controls.Add($btnNet)

  $loadNet = {
    $nlv.Items.Clear()
    foreach ($r in @(Get-NetFindings)) {
      $it = New-Object Windows.Forms.ListViewItem($r.Adapter)
      [void]$it.SubItems.Add($r.Setting)
      [void]$it.SubItems.Add($r.Current)
      [void]$it.SubItems.Add($r.Target)
      [void]$it.SubItems.Add('')
      $it.Tag = $r
      [void]$nlv.Items.Add($it)
    }
    # an empty grid is just dead space - drop it and let the report fill the pane
    $nlv.Visible = ($nlv.Items.Count -gt 0)
    $btnNet.Visible = ($nlv.Items.Count -gt 0)
    $ntextCard.Top = $(if ($nlv.Visible) { 212 } else { 12 })
    $ntextCard.Height = $(if ($nlv.Visible) { 240 } else { 440 })

    $head = if ($nlv.Items.Count -eq 0) {
      'Nothing to change - every power saving setting this tool checks is already off.'
    } else {
      "{0} setting(s) worth turning off. Tick and press Apply.{1}" -f $nlv.Items.Count,
        $(if (Test-Admin) { '' } else { '  Needs administrator - use the button on the first tab.' })
    }
    $ntext.Text = $head + "`r`n`r`n" + ((Get-NetNotes) -join "`r`n")
  }

  $nlv.Add_ItemSelectionChanged({
    if ($nlv.SelectedItems.Count -gt 0) { $ntext.Text = $nlv.SelectedItems[0].Tag.Why + "`r`n`r`n" + $ntext.Text.Substring($ntext.Text.IndexOf("`r`n`r`n") + 4) }
  })

  $btnNet.Add_Click({
    $items = @($nlv.CheckedItems)
    if ($items.Count -eq 0) {
      [void][Windows.Forms.MessageBox]::Show('Tick at least one row first.', 'TsakasOptimizer')
      return
    }
    $names = ($items | ForEach-Object { "{0}: {1}" -f $_.Tag.Adapter, $_.Tag.Setting }) -join "`r`n"
    $ans = [Windows.Forms.MessageBox]::Show(
      "Apply these $($items.Count) change(s)?`r`n`r`n$names`r`n`r`nThe adapter resets, so the connection drops for a second or two.",
      'TsakasOptimizer', 'YesNo', 'Question')
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
  $alv.Size = New-Object Drawing.Size(800, 260)
  $alv.Anchor = 'Top,Left,Right'
  foreach ($c in @(@('App', 100), @('Action', 100), @('Current state', 180), @('Result', 120), @('What it does', 300))) {
    [void]$alv.Columns.Add($c[0], $c[1])
  }
  $tab5.Controls.Add($alv)

  $atext = New-Object Windows.Forms.TextBox
  $atext.Multiline = $true; $atext.ReadOnly = $true; $atext.ScrollBars = 'Vertical'
  $atext.Location = New-Object Drawing.Point(12, 282)
  $atext.Size = New-Object Drawing.Size(800, 170)
  $atext.Anchor = 'Top,Left,Right,Bottom'
  $atext.Text = 'Select a row to see why it is listed.'
  $tab5.Controls.Add($atext)

  $btnApps = New-Object Windows.Forms.Button
  $btnApps.Text = 'Apply selected'
  $btnApps.Location = New-Object Drawing.Point(12, 462)
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
      [void][Windows.Forms.MessageBox]::Show('Tick at least one row first.', 'TsakasOptimizer')
      return
    }
    $names = ($items | ForEach-Object { "$($_.Tag.App): $($_.Tag.Action)" }) -join "`r`n"
    $ans = [Windows.Forms.MessageBox]::Show(
      "Apply these changes?`r`n`r`n$names", 'TsakasOptimizer', 'YesNo', 'Question')
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
  $rowHeight.ImageSize = New-Object Drawing.Size(1, 28)
  foreach ($l in @($lv, $mlv, $blv, $nlv, $alv)) {
    $l.SmallImageList = $rowHeight
    $l.BorderStyle = 'None'
    $l.HeaderStyle = 'Nonclickable'
    $l.Font = New-Object Drawing.Font($family, 10)
  }
  # the reports are prose, so a proportional face reads far better than Consolas
  foreach ($t in @($details, $mtext, $btext, $ntext, $atext)) {
    $t.BackColor = $white
    $t.ForeColor = $ink
    $t.Font = New-Object Drawing.Font($family, 10)
  }
  $details.ForeColor = $muted
  $detailsCard = Add-PaddedCard $details 10 $line 8
  $mtextCard   = Add-PaddedCard $mtext   10 $line 14
  $btextCard   = Add-PaddedCard $btext   10 $line 14
  $ntextCard   = Add-PaddedCard $ntext   10 $line 14
  $atextCard   = Add-PaddedCard $atext   10 $line 14
  foreach ($c in @($lv, $mlv, $blv, $nlv, $alv)) {
    Set-Rounded $c 10
    Add-Hairline $c $line 10
  }

  & $selectSection 0

  # bottom-right of the tab page, once the real sizes exist
  $form.Add_Shown({
    $btnElev.Left = $tab1.ClientSize.Width - $btnElev.Width - 12
    $btnElev.Top  = $btnApply.Top
  })

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
    @{N = 'sticks in A1/B1 are flagged';          R = ((Get-MemoryNotes $slot13 4 $cpu) -join "`n") -match 'FIRST slot'}
    @{N = 'both sticks one channel is flagged';   R = ((Get-MemoryNotes $oneCh 4 $cpu) -join "`n") -match 'same channel'}
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
    @{N = 'network scan runs without error';      R = ((@(Get-NetFindings)).Count -ge 0)}
    # motherboard tab
    @{N = 'a 2 year old BIOS is flagged';         R = ((Get-BiosNotes ([pscustomobject]@{Vendor='X';Model='Y';Bios='F1';BiosDate=(Get-Date).AddMonths(-24);AgeMonths=24;Cpu='AMD Ryzen 7 7800X3D'}) ) -join "`n") -match 'over 18 months old'}
    @{N = 'a recent BIOS is not flagged';         R = ((Get-BiosNotes ([pscustomobject]@{Vendor='X';Model='Y';Bios='F1';BiosDate=(Get-Date).AddMonths(-2);AgeMonths=2;Cpu='AMD Ryzen 7 7800X3D'}) ) -join "`n") -match 'BIOS is recent'}
    @{N = 'AM5 gets the AGESA note';              R = ((Get-BiosNotes ([pscustomobject]@{Vendor='X';Model='Y';Bios='F1';BiosDate=(Get-Date).AddMonths(-2);AgeMonths=2;Cpu='AMD Ryzen 7 7800X3D'}) ) -join "`n") -match 'AGESA'}
    @{N = 'generic Microsoft driver is called out'; R = ((Get-DriverNote 'Microsoft' (Get-Date)) -match 'generic Windows driver')}
    @{N = 'an old driver is called out';          R = ((Get-DriverNote 'Realtek' ((Get-Date).AddYears(-4))) -match 'over 3 years old')}
    @{N = 'a current vendor driver is silent';    R = ((Get-DriverNote 'Realtek' (Get-Date)) -eq '')}
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
