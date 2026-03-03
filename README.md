# 🔧 Fix-ClaudeDesktop

**One-click fix for Claude Desktop (Cowork) crashes, freezes, and VM errors on Windows.**

No questions, no interaction, no PC reboot. Double-click → fixed → back to work.

---

## The Problem

Claude Desktop (Cowork) runs a lightweight VM via `CoworkVMService` to power its workspace. This VM frequently gets stuck in broken states:

```
RPC error -1: failed to ensure virtiofs mount: Plan9 mount failed: bad address
```

```
VM service not running. The service failed to start.
```

When this happens, Claude Desktop becomes unusable. Closing and reopening the app doesn't help — the VM service stays broken. The typical "fix" is rebooting the entire PC.

**This script does what a reboot does, in ~15 seconds.**

---

## What It Does

| Step | Action |
|------|--------|
| 1 | Force-kills all `claude.exe` processes |
| 2 | Stops `CoworkVMService` (8s graceful timeout, then `taskkill`) |
| 3 | Verifies no orphan processes remain |
| 4 | Deletes VM cache (`claude-code-vm` + `vm_bundles`) to force clean rebuild |
| 5 | Restarts `CoworkVMService` with cascading fallbacks |
| 6 | Auto-detects and relaunches `Claude.exe` |

### What It Does NOT Touch

- ✅ `claude_desktop_config.json` — your MCP servers and settings
- ✅ `config.json` — app configuration
- ✅ Conversations — stored server-side, not in the local VM
- ✅ All other app data

---

## Installation

1. Download `Fix-ClaudeDesktop.ps1` and `Fix-ClaudeDesktop.bat`
2. Place both in the **same folder** (e.g., `C:\Tools\ClaudeFix\`)
3. Right-click `Fix-ClaudeDesktop.bat` → **Send to** → **Desktop (create shortcut)**

Done. Double-click the shortcut whenever Claude breaks.

> The script auto-elevates to Administrator via UAC prompt, which is required to manage the Windows service.

---

## Usage

Double-click. That's it. No questions, no input needed.

```
  =========================================
   CLAUDE DESKTOP / COWORK - RESET & FIX
  =========================================

[1/6] Chiusura processi Claude...
      Killati 7 processi Claude
[2/6] Arresto servizio CoworkVMService...
      Servizio arrestato
[3/6] Verifica processi residui...
      Tutto pulito
[4/6] Reset cache VM...
      claude-code-vm eliminata
      vm_bundles eliminata
[5/6] Riavvio servizio CoworkVMService...
      Servizio avviato
[6/6] Avvio Claude Desktop...
      Claude avviato: C:\Users\...\Claude.exe

  =========================================
           OPERAZIONE COMPLETATA
  =========================================

  Servizio VM:     Running
  Processi Claude: 1 attivi

  Premi un tasto per chiudere...
```

> First launch after reset takes slightly longer as Claude rebuilds the VM from scratch.

---

## How Claude.exe Is Found

The script searches for the executable in this order:

1. Common install paths (`LocalAppData\Programs\claude\`, `Program Files\`, etc.)
2. Windows Registry uninstall keys (`HKLM` + `HKCU`)
3. Start Menu shortcuts (`.lnk` target resolution)
4. Brute-force scan of `LocalAppData` (depth 4)

If all four methods fail, it asks you to launch Claude manually from the Start Menu.

---

## How It Works (Technical)

Claude Desktop's Cowork runs a lightweight VM managed by the `CoworkVMService` Windows service (`cowork-svc.exe`). The VM uses **VirtioFS** via Plan9 protocol to share the filesystem between host and guest.

VM state lives in two directories:

```
%APPDATA%\Claude\claude-code-vm\    ← VM image and runtime
%APPDATA%\Claude\vm_bundles\        ← execution bundles
```

When the VM mount corrupts (after sleep/hibernate, crashes, or forced shutdowns), these files become inconsistent. The service enters a failed state that persists because the app doesn't rebuild the VM on its own.

This script breaks the cycle by killing everything, deleting the stale VM files, and restarting the service clean.

---

## Requirements

- Windows 10/11
- Claude Desktop with Cowork installed
- Administrator privileges (auto-requested)

---

## Troubleshooting

**"Processi resistono" warning** — In rare cases a process is unkillable. A PC reboot is the only option, but this is extremely uncommon.

**"Claude.exe non trovato"** — Your installation is in a non-standard path. Launch Claude manually from the Start Menu after the script completes. Consider opening an issue with your install path so we can add it.

**Script doesn't run** — Make sure both `.ps1` and `.bat` are in the same folder. The `.bat` calls the `.ps1` using a relative path.

---

## License

MIT

---

*Built out of frustration with rebooting the PC every time Claude Desktop decides to break.*
