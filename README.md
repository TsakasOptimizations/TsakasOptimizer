# Optimizer

A single PowerShell script that looks at what is running on a Windows PC, points
out what is safe to close or set to Manual, and asks before changing anything.
No installer, no dependencies, no telemetry.

## Run it

One line, nothing to download, always the current version:

```
irm https://raw.githubusercontent.com/TsakasOptimizations/Optimizer/main/Optimizer.ps1 | iex
```

Paste that into any PowerShell window and the app opens. Execution policy does
not apply, because nothing is saved to disk.

To keep a copy instead, download the folder and double-click `Optimizer.cmd`. It
works from anywhere, because it resolves its own folder.

From a terminal, either cd into the folder first:

```
cd C:\path\to\Optimizer
powershell -ExecutionPolicy Bypass -File .\Optimizer.ps1
```

or give the full path, which works from any directory:

```
powershell -ExecutionPolicy Bypass -File "C:\path\to\Optimizer\Optimizer.ps1"
```

If Windows blocks the download, right-click the file, Properties, tick Unblock.

Run it as administrator if you want service changes to apply - the window has a
button that restarts it elevated.

## What it looks at

**Processes and services tab.** Two passes:

1. A catalog of common software (launchers, chat apps, updaters, remote desktop,
   peripheral suites) with specific advice for each.
2. Anything the catalog has never heard of is scored on behaviour instead:
   does it start itself with Windows, does it have a window open, does its name
   look like a helper or updater, how much memory it holds. Only things that
   score high enough are listed, and the reasons are shown.

Nothing is ticked for you. Processes are closed; services are set to Manual,
which is reversible with the Undo button.

Never suggested: Windows components, anything under `C:\Windows`, anything whose
executable cannot be read, and anything that looks like antivirus, firewall,
VPN, audio, drivers, storage or virtualisation.

**Memory tab.** Reads the DIMMs and reports whether EXPO/XMP is actually loaded,
whether two sticks sit in the correct slots, mixed kits, and the tuning targets
for the detected platform. Read-only - it never touches the BIOS.

Windows does not expose live memory timings, so the timings shown come from the
SPD/rated profile. Verify the loaded values in BIOS, ZenTimings or CPU-Z.

## Switches

| Switch | What it does |
|---|---|
| *(none)* | Opens the window |
| `-Console` | Text mode, asks y/n per item |
| `-Report` | Lists findings, changes nothing |
| `-Undo` | Restores service start types this tool changed |
| `-SelfTest` | Runs the built-in checks |

## Updates

`Check for updates` compares the `$Version` line in this script against the copy
published at `$RawUrl`, and a blue dot appears when a newer one exists. If you
started it with the one-liner above there is nothing to update - you already
fetched the latest copy.

To publish your own build, set `$Repo` at the top of `Optimizer.ps1` to your
repo (`owner/name`), then bump `$Version` with every release.
