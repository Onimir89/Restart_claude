<# 
    ╔══════════════════════════════════════════════════════════════╗
    ║           CLAUDE DESKTOP / COWORK - RESET & FIX            ║
    ║                                                            ║
    ║  Risolve errori VirtioFS, mount Plan9, e blocchi della     ║
    ║  VM di Claude Desktop (Cowork).                            ║
    ║                                                            ║
    ║  Cosa fa:                                                  ║
    ║  1. Killa tutti i processi Claude                          ║
    ║  2. Ferma il servizio CoworkVMService                      ║
    ║  3. (Opzionale) Cancella la cache VM per reset completo    ║
    ║  4. Riavvia Claude Desktop                                 ║
    ║                                                            ║
    ║  NON tocca: config MCP, impostazioni, conversazioni        ║
    ╚══════════════════════════════════════════════════════════════╝
#>

# ── Richiedi privilegi Admin se non li abbiamo ──
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "`n[!] Riavvio con privilegi di amministratore..." -ForegroundColor Yellow
    Start-Process PowerShell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$ErrorActionPreference = "SilentlyContinue"
$claudeAppData = "$env:APPDATA\Claude"

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   CLAUDE DESKTOP / COWORK - RESET & FIX     ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ══════════════════════════════════════════════════
# STEP 1: Killa tutti i processi Claude
# ══════════════════════════════════════════════════
Write-Host "[1/4] Chiusura processi Claude..." -ForegroundColor Yellow

$claudeProcs = Get-Process | Where-Object { $_.Name -match "^claude$" }
if ($claudeProcs) {
    $claudeProcs | Stop-Process -Force
    Write-Host "      Killati $($claudeProcs.Count) processi Claude" -ForegroundColor Green
} else {
    Write-Host "      Nessun processo Claude trovato" -ForegroundColor DarkGray
}
Start-Sleep -Seconds 1

# ══════════════════════════════════════════════════
# STEP 2: Ferma il servizio CoworkVMService
# ══════════════════════════════════════════════════
Write-Host "[2/4] Arresto servizio CoworkVMService..." -ForegroundColor Yellow

$svc = Get-Service -Name "CoworkVMService" -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -eq "Running") {
        # Prima prova Stop-Service con timeout
        $job = Start-Job -ScriptBlock { Stop-Service -Name "CoworkVMService" -Force }
        $completed = $job | Wait-Job -Timeout 15

        if (-not $completed) {
            # Se non risponde, forza con taskkill
            Write-Host "      Stop-Service lento, forzo con taskkill..." -ForegroundColor DarkYellow
            $job | Stop-Job | Remove-Job -Force
            
            $coworkProc = Get-Process -Name "cowork-svc" -ErrorAction SilentlyContinue
            if ($coworkProc) {
                taskkill /F /PID $coworkProc.Id 2>$null | Out-Null
            }
            # Fallback: taskkill per nome
            taskkill /F /IM "cowork-svc.exe" 2>$null | Out-Null
        } else {
            $job | Remove-Job -Force
        }
        Write-Host "      Servizio CoworkVMService arrestato" -ForegroundColor Green
    } else {
        Write-Host "      Servizio gia' fermo" -ForegroundColor DarkGray
    }
} else {
    Write-Host "      Servizio CoworkVMService non trovato" -ForegroundColor DarkGray
}
Start-Sleep -Seconds 2

# ══════════════════════════════════════════════════
# STEP 3: Verifica che tutto sia morto
# ══════════════════════════════════════════════════
Write-Host "[3/4] Verifica processi residui..." -ForegroundColor Yellow

$remaining = Get-Process | Where-Object { $_.Name -match "^(claude|cowork)" }
if ($remaining) {
    Write-Host "      Processi residui trovati, forzo chiusura..." -ForegroundColor DarkYellow
    $remaining | ForEach-Object {
        taskkill /F /PID $_.Id 2>$null | Out-Null
    }
    Start-Sleep -Seconds 2
    
    $stillRunning = Get-Process | Where-Object { $_.Name -match "^(claude|cowork)" }
    if ($stillRunning) {
        Write-Host "      [!] ATTENZIONE: alcuni processi resistono. Potrebbe servire un riavvio PC." -ForegroundColor Red
        $stillRunning | Format-Table Name, Id -AutoSize
    } else {
        Write-Host "      Tutti i processi eliminati" -ForegroundColor Green
    }
} else {
    Write-Host "      Tutto pulito" -ForegroundColor Green
}

# ══════════════════════════════════════════════════
# STEP 4: Reset VM (opzionale)
# ══════════════════════════════════════════════════
Write-Host ""
Write-Host "  ┌──────────────────────────────────────────────┐" -ForegroundColor White
Write-Host "  │  Vuoi anche resettare la VM?                 │" -ForegroundColor White
Write-Host "  │                                              │" -ForegroundColor White
Write-Host "  │  Cancella claude-code-vm e vm_bundles        │" -ForegroundColor White
Write-Host "  │  (NON tocca config, MCP, conversazioni)      │" -ForegroundColor White
Write-Host "  │                                              │" -ForegroundColor White
Write-Host "  │  Fallo se hai l'errore VirtioFS/Plan9        │" -ForegroundColor White
Write-Host "  └──────────────────────────────────────────────┘" -ForegroundColor White
Write-Host ""

$resetVM = Read-Host "  Resettare la VM? (S/N) [default: N]"

if ($resetVM -eq "S" -or $resetVM -eq "s") {
    Write-Host ""
    Write-Host "[4/4] Reset cache VM..." -ForegroundColor Yellow
    
    $vmPath = Join-Path $claudeAppData "claude-code-vm"
    $bundlePath = Join-Path $claudeAppData "vm_bundles"
    
    if (Test-Path $vmPath) {
        Remove-Item $vmPath -Recurse -Force
        Write-Host "      claude-code-vm eliminata" -ForegroundColor Green
    } else {
        Write-Host "      claude-code-vm non presente" -ForegroundColor DarkGray
    }
    
    if (Test-Path $bundlePath) {
        Remove-Item $bundlePath -Recurse -Force
        Write-Host "      vm_bundles eliminata" -ForegroundColor Green
    } else {
        Write-Host "      vm_bundles non presente" -ForegroundColor DarkGray
    }
    
    Write-Host "      VM resettata. Sara' ricreata al prossimo avvio." -ForegroundColor Green
} else {
    Write-Host "[4/4] Reset VM saltato" -ForegroundColor DarkGray
}

# ══════════════════════════════════════════════════
# STEP 5: Riavvia Claude Desktop
# ══════════════════════════════════════════════════
Write-Host ""
$restart = Read-Host "  Riavviare Claude Desktop ora? (S/N) [default: S]"

if ($restart -ne "N" -and $restart -ne "n") {
    Write-Host ""
    Write-Host "  Avvio Claude Desktop..." -ForegroundColor Cyan
    
    # Cerca l'eseguibile di Claude
    $claudeExe = $null
    $possiblePaths = @(
        "$env:LOCALAPPDATA\Programs\claude\Claude.exe",
        "$env:LOCALAPPDATA\claude\Claude.exe",
        "$env:ProgramFiles\Claude\Claude.exe",
        "${env:ProgramFiles(x86)}\Claude\Claude.exe"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $claudeExe = $path
            break
        }
    }
    
    # Fallback: cerca nello Start Menu
    if (-not $claudeExe) {
        $shortcut = Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu" -Recurse -Filter "Claude*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($shortcut) {
            $shell = New-Object -ComObject WScript.Shell
            $claudeExe = $shell.CreateShortcut($shortcut.FullName).TargetPath
        }
    }
    
    if ($claudeExe -and (Test-Path $claudeExe)) {
        Start-Process $claudeExe
        Write-Host "  Claude Desktop avviato!" -ForegroundColor Green
    } else {
        Write-Host "  [!] Eseguibile non trovato automaticamente." -ForegroundColor Yellow
        Write-Host "      Avvia Claude Desktop manualmente dal menu Start." -ForegroundColor Yellow
    }
}

# ══════════════════════════════════════════════════
# FINE
# ══════════════════════════════════════════════════
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║              OPERAZIONE COMPLETATA           ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Premi un tasto per chiudere..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
