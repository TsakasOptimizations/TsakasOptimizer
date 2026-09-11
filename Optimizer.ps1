#requires -Version 5.1
<#
  Optimizer.ps1 - scans running processes + auto-start services, flags the ones
  commonly safe to close or switch to Manual, and asks before touching anything.
  Service changes are logged so -Undo can put them back.
  #>
[CmdletBinding()]
param([switch]$Console, [switch]$Report, [switch]$Undo, [switch]$SelfTest)

$Version = '1.0.2'
$Repo    = 'TsakasOptimizations/Optimizer'
$Branch  = 'main'
$RawUrl  = "https://raw.githubusercontent.com/$Repo/$Branch/Optimizer.ps1"

$Root = if ($PSScriptRoot) { $PSScriptRoot } else { Join-Path $env:LOCALAPPDATA 'Optimizer' }
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
      Set-Service -Name $e.Name -StartupType $e.Previous
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

# --- gui ---------------------------------------------------------------------
function Show-Gui {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing

  $form = New-Object Windows.Forms.Form
  $form.Text = "Optimizer $Version"
  $form.ClientSize = New-Object Drawing.Size(836, 584)
  $form.MinimumSize = New-Object Drawing.Size(700, 520)
  $form.StartPosition = 'CenterScreen'
  $form.Font = New-Object Drawing.Font('Segoe UI', 9)

  $accent = [Drawing.Color]::FromArgb(0, 103, 192)
  $ink    = [Drawing.Color]::FromArgb(32, 32, 32)
  $muted  = [Drawing.Color]::FromArgb(96, 100, 108)
  $line   = [Drawing.Color]::FromArgb(214, 217, 222)
  $panel  = [Drawing.Color]::FromArgb(246, 247, 249)
  $form.BackColor = $panel
  $form.ForeColor = $ink

  $flat = {
    param($b, $primary)
    $b.FlatStyle = 'Flat'
    $b.Cursor = 'Hand'
    $b.FlatAppearance.BorderSize = 1
    if ($primary) {
      $b.BackColor = $accent; $b.ForeColor = [Drawing.Color]::White
      $b.FlatAppearance.BorderColor = $accent
      $b.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
    } else {
      $b.BackColor = [Drawing.Color]::White; $b.ForeColor = $ink
      $b.FlatAppearance.BorderColor = $line
    }
  }

  $tabs = New-Object Windows.Forms.TabControl
  $tabs.Location = New-Object Drawing.Point(0, 0)
  $tabs.Size = New-Object Drawing.Size(836, 536)
  $tabs.Anchor = 'Top,Left,Right,Bottom'
  $tabs.Padding = New-Object Drawing.Point(14, 5)
  $tab1 = New-Object Windows.Forms.TabPage; $tab1.Text = 'Processes and services'
  $tab2 = New-Object Windows.Forms.TabPage; $tab2.Text = 'Memory'
  foreach ($t in @($tab1, $tab2)) { $t.BackColor = [Drawing.Color]::White; $t.UseVisualStyleBackColor = $false }
  $tabs.TabPages.AddRange(@($tab1, $tab2))
  $form.Controls.Add($tabs)
  # a TabPage defaults to 200x100; set the real size before adding anchored children
  $pageSize = New-Object Drawing.Size($tabs.DisplayRectangle.Width, $tabs.DisplayRectangle.Height)
  $tab1.Size = $pageSize
  $tab2.Size = $pageSize

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
  $btnUndo    = & $mkButton 'Undo changes'   248 110
  $btnElev    = & $mkButton 'Restart app as admin' 366 160
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
      [void]$it.SubItems.Add($(if ($f.Action -eq 'Kill') { 'close it now' } else { 'set to Manual (starts on demand)' }))
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
  $footer.Location = New-Object Drawing.Point(0, 536)
  $footer.Size = New-Object Drawing.Size(836, 48)
  $footer.Anchor = 'Left,Right,Bottom'
  $footer.BackColor = $panel
  $form.Controls.Add($footer)

  $contact = New-Object Windows.Forms.LinkLabel
  $contact.AutoSize = $true
  $contact.Location = New-Object Drawing.Point(14, 16)
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
      "Version $($script:online.Version) is available (you have $Version).`r`n`r`nDownload it and restart Optimizer?",
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
      [void][Windows.Forms.MessageBox]::Show('Tick at least one row first.', 'Optimizer')
      return
    }
    $names = ($items | ForEach-Object { $_.Tag.Label }) -join "`r`n"
    $ans = [Windows.Forms.MessageBox]::Show(
      "Apply to these $($items.Count) item(s)?`r`n`r`n$names", 'Optimizer', 'YesNo', 'Question')
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

  # bottom-right of the tab page, once the real sizes exist
  $form.Add_Shown({
    $btnElev.Left = $tab1.ClientSize.Width - $btnElev.Width - 12
    $btnElev.Top  = $tab1.ClientSize.Height - $btnElev.Height - 12
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
Write-Host '  Optimizer - scanning processes and auto-start services...' -ForegroundColor Cyan
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
  Write-Host ("  Done. Freed about {0} MB. Undo service changes with: .\Optimizer.ps1 -Undo" -f [math]::Round($freed,1)) -ForegroundColor Cyan
}
Write-Host ''
