<img src="logo.png" alt="TsakasOptimizer" width="420">

# TsakasOptimizer

A single PowerShell script that looks at what is running on a Windows PC, points
out what is safe to close or set to Manual, and asks before changing anything.
One file, no dependencies, no telemetry, no admin rights to install.

## Install

One line in any PowerShell window. No admin rights, nothing to unzip:

```
irm https://raw.githubusercontent.com/TsakasOptimizations/TsakasOptimizer/main/install.ps1 | iex
```

That installs TsakasOptimizer to `%LOCALAPPDATA%\TsakasOptimizer`, adds a Start Menu and a
desktop shortcut, and opens it. It stays on the PC - launch it any time from the
Start Menu. To update later, open it and press `Check for updates`.

Run the same line again to reinstall or repair.

### Run it as administrator

Service changes need admin rights. The window has a button that restarts it
elevated, or right-click the shortcut and choose Run as administrator.

### Without installing

Download the folder and double-click `TsakasOptimizer.cmd`, which resolves its own
folder and works from anywhere. From a terminal, cd into the folder first:

```
cd C:\path\to\TsakasOptimizer
powershell -ExecutionPolicy Bypass -File .\TsakasOptimizer.ps1
```

If Windows blocks the download, right-click the file, Properties, tick Unblock.

### Uninstall

```
Remove-Item "$env:LOCALAPPDATA\TsakasOptimizer" -Recurse -Force
Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\TsakasOptimizer.lnk", "$env:USERPROFILE\Desktop\TsakasOptimizer.lnk" -Force
```

Anything you changed stays changed after uninstalling. Set services back in
`services.msc` and settings back in the Settings app if you want them.

## What it looks at

**Processes and services tab.** Two passes:

1. A catalog of common software (launchers, chat apps, updaters, remote desktop,
   peripheral suites) with specific advice for each.
2. Anything the catalog has never heard of is scored on behaviour instead:
   does it start itself with Windows, does it have a window open, does its name
   look like a helper or updater, how much memory it holds. Things that score
   high enough go under *Suggested processes* or *Suggested services*, with
   the reasons shown.

Every process and service is listed underneath, grouped, with a live count at
the top and an information mark on each row that looks it up. Nothing is ticked
for you. Processes are closed; a service steps down one notch - Automatic to
Manual, Manual to Disabled. Windows' own processes and services can be ticked
too, but the confirmation names them and says what can break.

**App Optimizer tab.** Everything that starts with Windows - Run keys, the
Startup folders and logon scheduled tasks - with a switch to stop each one.
Startup-folder shortcuts are moved to `startup-disabled` rather than deleted.
It also sizes the caches worth clearing (Delivery Optimization, Windows Update,
NVIDIA, DirectX and Steam shader caches, temp files, crash dumps, and around
twenty apps' own caches) and offers a short, curated list of Store apps to
remove. Removing a Store app has no way back except reinstalling it.

**Windows Settings tab.** Switches for performance, privacy and the suggestions
Windows shows you - Game Bar recording, GPU scheduling, fast startup, pointer
acceleration, advertising ID, diagnostic data, activity history, Start menu
suggestions, widgets, Copilot and more. Each applies the moment it is flipped.

Never suggested: Windows components, anything under `C:\Windows`, anything whose
executable cannot be read, and anything that looks like antivirus, firewall,
VPN, audio, drivers, storage or virtualisation.

**Memory tab.** Reads the DIMMs and reports whether EXPO/XMP is actually loaded,
whether two sticks sit in the correct slots, mixed kits, and the tuning targets
for the detected platform. Read-only - it never touches the BIOS.

Windows does not expose live memory timings, so the timings shown come from the
SPD/rated profile. Verify the loaded values in BIOS, ZenTimings or CPU-Z.

**Network tab.** Three groups:

- *Power saving* - Energy-Efficient Ethernet, Green Ethernet, adapter power
  saving and "allow the computer to turn off this device". Worth turning off on
  a desktop.
- *Latency (optional)* - Interrupt Moderation and TCP/UDP checksum offload.
  Turning them off trades CPU time for response; test before keeping them.
- *Repair* - a leftover `DisableTaskOffload` registry value that turns every
  offload off and stops Receive Side Scaling from working.

It also reports Receive Side Scaling status, receive/transmit buffers and the
negotiated link speed. Large Send Offload and Receive Segment Coalescing are
left alone because they only affect TCP, not the UDP traffic games use, and
pinning interrupts to specific CPU cores is left as a manual step because the
right cores depend on the CPU.

## Switches

| Switch | What it does |
|---|---|
| *(none)* | Opens the window, asking for Administrator first |
| `-SelfTest` | Runs the built-in checks |

## Updates

`Check for updates` compares the `$Version` line in the installed script against
the copy published at `$RawUrl`. A blue dot appears when a newer one exists;
accepting it backs the current file up as `TsakasOptimizer.ps1.bak`, writes the new
version and restarts. It also refreshes the files that ship beside the script
(the icon) and repoints the shortcuts, so an in-app update matches a fresh
install.

To publish your own build, set `$Repo` at the top of `TsakasOptimizer.ps1` to your
repo (`owner/name`), then bump `$Version` with every release.
