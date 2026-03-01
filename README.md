# 🔧 Fix-ClaudeDesktop

**One-click fix for Claude Desktop (Cowork) crashes, freezes, and VM errors on Windows.**

Resolves common issues including `VirtioFS mount failed: bad address`, `Plan9 mount failed`, `VM service not running`, and unresponsive Claude Desktop states that normally require a full PC reboot.

---

## The Problem

Claude Desktop (Cowork) runs a lightweight VM via `CoworkVMService` to power its workspace. This VM frequently gets stuck in broken states, causing errors like:

```
RPC error -1: failed to ensure virtiofs mount: Plan9 mount failed: bad address
```

```
VM service not running. The service failed to start.
```

When this happens, Claude Desktop becomes unusable. Closing and reopening the app doesn't help because the underlying VM service remains in a corrupted state. The typical "fix" is rebooting the entire PC — which is slow and disruptive.

**This script eliminates the need to reboot.**

---

## What It Does

| Step | Action | Details |
|------|--------|---------|
| 1 | **Kill Claude processes** | Force-stops all `claude.exe` instances |
| 2 | **Stop CoworkVMService** | Graceful stop with 15s timeout, falls back to `taskkill` if hung |
| 3 | **Verify cleanup** | Ensures no orphan processes remain |
| 4 | **Reset VM cache** *(optional)* | Deletes `claude-code-vm` and `vm_bundles` to force VM rebuild |
| 5 | **Restart CoworkVMService** | Brings the VM service back up with multiple fallback strategies |
| 6 | **Relaunch Claude Desktop** | Auto-detects and starts `Claude.exe` |

### What It Does NOT Touch

- ✅ `claude_desktop_config.json` — your MCP servers and settings are safe
- ✅ `config.json` — app configuration preserved
- ✅ Conversations — stored server-side by Anthropic, not in the local VM
- ✅ All other app data — only VM runtime files are affected (and only when you choose to reset)

---

## Installation

### Quick Setup

1. Download both files:
   - `Fix-ClaudeDesktop.ps1`
   - `Fix-ClaudeDesktop.bat`

2. Place them in the **same folder** (e.g., `C:\Tools\ClaudeFix\`)

3. Right-click `Fix-ClaudeDesktop.bat` → **Send to** → **Desktop (create shortcut)**

4. *(Optional)* Rename the shortcut to something like "Fix Claude" and change its icon

### That's it. Double-click the desktop shortcut whenever Claude breaks.

> **Note:** The script auto-elevates to Administrator — you'll see a UAC prompt, which is required to manage the `CoworkVMService` Windows service.

---

## Usage

### Scenario 1: Claude Desktop is frozen or unresponsive

The app won't close, workspace hangs, or you get generic errors.

```
Double-click "Fix Claude" on Desktop

[1/6] Chiusura processi Claude...
      Killati 8 processi Claude
[2/6] Arresto servizio CoworkVMService...
      Servizio CoworkVMService arrestato
[3/6] Verifica processi residui...
      Tutto pulito

  Resettare la VM? (S/N) [default: N]: N     ← just press Enter

[4/6] Reset VM saltato
[5/6] Riavvio servizio CoworkVMService...
      Servizio CoworkVMService avviato con successo
  Riavviare Claude Desktop ora? (S/N) [default: S]:     ← just press Enter

[6/6] Avvio Claude Desktop...
      Claude Desktop avviato

  ╔══════════════════════════════════════════════╗
  ║              OPERAZIONE COMPLETATA           ║
  ╚══════════════════════════════════════════════╝

  Stato servizio VM:  Running
  Processi Claude:    1 attivi
```

### Scenario 2: VirtioFS / Plan9 mount error

You see `Plan9 mount failed: bad address` or `failed to ensure virtiofs mount`.

```
Double-click "Fix Claude" on Desktop

[1/6] Chiusura processi Claude...
      Killati 5 processi Claude
[2/6] Arresto servizio CoworkVMService...
      Stop-Service lento, forzo con taskkill...
      Servizio CoworkVMService arrestato
[3/6] Verifica processi residui...
      Tutto pulito

  Resettare la VM? (S/N) [default: N]: S     ← type S for VirtioFS errors

[4/6] Reset cache VM...
      claude-code-vm eliminata
      vm_bundles eliminata
      VM resettata. Sara' ricreata al prossimo avvio.
[5/6] Riavvio servizio CoworkVMService...
      Servizio CoworkVMService avviato con successo
  Riavviare Claude Desktop ora? (S/N) [default: S]:     ← press Enter

[6/6] Avvio Claude Desktop...
      Claude Desktop avviato

  ╔══════════════════════════════════════════════╗
  ║              OPERAZIONE COMPLETATA           ║
  ╚══════════════════════════════════════════════╝

  Stato servizio VM:  Running
  Processi Claude:    1 attivi
```

> **Note:** First launch after a VM reset takes longer than usual as Claude rebuilds the VM from scratch.

### Scenario 3: VM service won't start (stubborn state)

The script handles this automatically with cascading fallbacks:

```
[5/6] Riavvio servizio CoworkVMService...
      [!] Errore avvio servizio: Cannot start service...
      Provo con sc.exe...
      Stato servizio: Running
```

---

## When to Use Each Option

| Symptom | Reset VM? |
|---------|-----------|
| Claude Desktop frozen / won't respond | **No** — just restart processes and service |
| `VM service not running` after force-closing Claude | **No** — service restart is enough |
| `Plan9 mount failed: bad address` | **Yes** — VM cache is corrupted |
| `VirtioFS mount failed` | **Yes** — VM needs a clean rebuild |
| Workspace loads but tools/commands fail | Try **No** first, then **Yes** if it persists |
| After Windows sleep/hibernate broke Claude | Try **No** first, then **Yes** if it persists |

---

## Requirements

- **OS:** Windows 10/11
- **Permissions:** Administrator (auto-requested via UAC)
- **Claude Desktop** installed (any recent version with Cowork)

---

## How It Works (Technical Details)

Claude Desktop's Cowork feature runs a lightweight VM managed by the `CoworkVMService` Windows service (process: `cowork-svc.exe`). The VM uses **VirtioFS** (via Plan9 protocol) to share the filesystem between the host and the guest OS.

The VM state is stored in two local directories:

```
%APPDATA%\Claude\claude-code-vm\    ← VM image and runtime state
%APPDATA%\Claude\vm_bundles\        ← execution bundles
```

When the VM mount corrupts (often after sleep/hibernate, crashes, or forced shutdowns), these files become inconsistent. The service enters a failed state that persists across Claude Desktop restarts because the app doesn't rebuild the VM on its own — it just tries to reconnect to the existing (broken) one.

This script breaks the cycle by:

1. Killing all Claude processes to release file locks
2. Stopping the service (with `taskkill` fallback for hung states)
3. Optionally deleting the VM state files to force a clean rebuild
4. Restarting the service so it initializes fresh
5. Relaunching the app to connect to the healthy VM

---

## Troubleshooting

**"Some processes resist" warning:**
In rare cases, a process may be unkillable. A PC reboot is the only option here, but this is extremely uncommon.

**"Executable not found" when relaunching:**
The script searches common installation paths. If your Claude Desktop is installed in a non-standard location, just launch it manually from the Start Menu after the script completes.

**Script doesn't run on double-click:**
Make sure both `.ps1` and `.bat` files are in the same folder. The `.bat` launcher calls the `.ps1` script using a relative path.

**UAC prompt doesn't appear:**
Run the `.bat` file manually as Administrator: right-click → "Run as administrator".

---

## License

MIT — Use it, modify it, share it.

---

## Contributing

Found an edge case? The VM service changed its name in a Claude update? Open an issue or PR.

---

*Built out of frustration with rebooting the PC every time Claude Desktop decides to break.*
