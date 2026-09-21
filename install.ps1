#requires -Version 5.1
<#
  Installs TsakasOptimizer to %LOCALAPPDATA%\TsakasOptimizer and adds Start Menu and desktop
  shortcuts. No admin rights needed. Run it again to reinstall or repair.

    irm https://raw.githubusercontent.com/TsakasOptimizations/TsakasOptimizer/main/install.ps1 | iex
#>
$ErrorActionPreference = 'Stop'

$Repo   = 'TsakasOptimizations/TsakasOptimizer'
$RawUrl = "https://raw.githubusercontent.com/$Repo/main/TsakasOptimizer.ps1"
$IconUrl = "https://raw.githubusercontent.com/$Repo/main/icon.ico"
$Dir    = Join-Path $env:LOCALAPPDATA 'TsakasOptimizer'
$Script = Join-Path $Dir 'TsakasOptimizer.ps1'
$Icon   = Join-Path $Dir 'icon.ico'

Write-Host ''
Write-Host '  Installing TsakasOptimizer...' -ForegroundColor Cyan

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$text = (Invoke-WebRequest -Uri $RawUrl -UseBasicParsing -TimeoutSec 20).Content
if ($text.Length -lt 5000 -or $text -notmatch 'function Show-Gui') {
  throw 'the download looks incomplete - try again'
}

if (-not (Test-Path $Dir)) { [void](New-Item -ItemType Directory -Path $Dir -Force) }
Set-Content -Path $Script -Value $text -Encoding UTF8

# the shortcut icon; not fatal if it cannot be fetched
try {
  Invoke-WebRequest -Uri $IconUrl -UseBasicParsing -TimeoutSec 20 -OutFile $Icon
} catch { $Icon = $null }

$version = if ($text -match "(?m)^\s*\`$Version\s*=\s*'([\d.]+)'") { $Matches[1] } else { '?' }

$shell = New-Object -ComObject WScript.Shell
$ps    = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$links = @(
  (Join-Path ([Environment]::GetFolderPath('Programs')) 'TsakasOptimizer.lnk')
  (Join-Path ([Environment]::GetFolderPath('Desktop'))  'TsakasOptimizer.lnk')
)
foreach ($lnk in $links) {
  $s = $shell.CreateShortcut($lnk)
  $s.TargetPath       = $ps
  $s.Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Script`""
  $s.WorkingDirectory = $Dir
  $s.Description      = 'Find background apps and services worth closing'
  if ($Icon -and (Test-Path $Icon)) { $s.IconLocation = $Icon }
  $s.Save()

  # "run as administrator" lives in a flag byte of the shortcut header, which
  # WScript.Shell cannot set
  try {
    $bytes = [IO.File]::ReadAllBytes($lnk)
    $bytes[0x15] = $bytes[0x15] -bor 0x20
    [IO.File]::WriteAllBytes($lnk, $bytes)
  } catch { }
}

Write-Host "  Installed version $version to $Dir" -ForegroundColor Green
Write-Host '  Shortcuts added to the Start Menu and desktop.' -ForegroundColor Green
Write-Host '  Updates: open it and press Check for updates.' -ForegroundColor DarkGray
Write-Host ''

Start-Process $ps -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $Script)
