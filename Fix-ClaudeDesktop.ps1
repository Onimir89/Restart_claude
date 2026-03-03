<# 
    CLAUDE DESKTOP / COWORK - RESET & FIX
    
    Kills all Claude processes, stops CoworkVMService,
    resets VM cache, restarts the service, relaunches Claude.
    
    Does NOT touch: config, MCP servers, conversations.
    Everything is automatic, no questions asked.
#>

# ── Admin elevation ──
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $scriptPath = $MyInvocation.MyCommand.Definition
    if (-not $scriptPath) { $scriptPath = $PSCommandPath }
    Start-Process PowerShell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    exit
}

Write-Host ""
Write-Host "  =========================================" -ForegroundColor Cyan
Write-Host "   CLAUDE DESKTOP / COWORK - RESET & FIX  " -ForegroundColor Cyan
Write-Host "  =========================================" -ForegroundColor Cyan
Write-Host ""

$claudeAppData = Join-Path $env:APPDATA "Claude"

# ══════════════════════════════════════════════════
# STEP 1: Kill all Claude processes
# ══════════════════════════════════════════════════
Write-Host "[1/6] Chiusura processi Claude..." -ForegroundColor Yellow

$claudeProcs = Get-Process -Name "claude" -ErrorAction SilentlyContinue
if ($claudeProcs) {
    $count = @($claudeProcs).Count
    $claudeProcs | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host "      Killati $count processi Claude" -ForegroundColor Green
} else {
    Write-Host "      Nessun processo Claude attivo" -ForegroundColor DarkGray
}
Start-Sleep -Seconds 1

# ══════════════════════════════════════════════════
# STEP 2: Stop CoworkVMService (8s timeout then taskkill)
# ══════════════════════════════════════════════════
Write-Host "[2/6] Arresto servizio CoworkVMService..." -ForegroundColor Yellow

$svc = Get-Service -Name "CoworkVMService" -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host "      Servizio non trovato" -ForegroundColor DarkGray
} elseif ($svc.Status -ne "Running") {
    Write-Host "      Servizio gia' fermo ($($svc.Status))" -ForegroundColor DarkGray
} else {
    $job = Start-Job -ScriptBlock { Stop-Service -Name "CoworkVMService" -Force 2>&1 }
    $finished = $job | Wait-Job -Timeout 8

    if ($finished) {
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        Write-Host "      Servizio arrestato" -ForegroundColor Green
    } else {
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        Write-Host "      Timeout, forzo con taskkill..." -ForegroundColor DarkYellow
        taskkill /F /IM "cowork-svc.exe" 2>$null | Out-Null
        $cp = Get-Process -Name "cowork-svc" -ErrorAction SilentlyContinue
        if ($cp) { taskkill /F /PID $cp.Id 2>$null | Out-Null }
        Write-Host "      Forzata chiusura" -ForegroundColor Green
    }
}
Start-Sleep -Seconds 1

# ══════════════════════════════════════════════════
# STEP 3: Verify everything is dead
# ══════════════════════════════════════════════════
Write-Host "[3/6] Verifica processi residui..." -ForegroundColor Yellow

$remaining = @(Get-Process | Where-Object { $_.Name -match "^(claude|cowork-svc)$" })
if ($remaining.Count -gt 0) {
    foreach ($proc in $remaining) {
        taskkill /F /PID $proc.Id 2>$null | Out-Null
    }
    Start-Sleep -Seconds 1
    $still = @(Get-Process | Where-Object { $_.Name -match "^(claude|cowork-svc)$" })
    if ($still.Count -gt 0) {
        Write-Host "      [!] $($still.Count) processi resistono - potrebbe servire riavvio PC" -ForegroundColor Red
    } else {
        Write-Host "      Eliminati $($remaining.Count) processi residui" -ForegroundColor Green
    }
} else {
    Write-Host "      Tutto pulito" -ForegroundColor Green
}

# ══════════════════════════════════════════════════
# STEP 4: Reset VM cache (always)
# ══════════════════════════════════════════════════
Write-Host "[4/6] Reset cache VM..." -ForegroundColor Yellow

$vmPath = Join-Path $claudeAppData "claude-code-vm"
$bundlePath = Join-Path $claudeAppData "vm_bundles"

if (Test-Path $vmPath) {
    Remove-Item $vmPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "      claude-code-vm eliminata" -ForegroundColor Green
} else {
    Write-Host "      claude-code-vm non presente" -ForegroundColor DarkGray
}

if (Test-Path $bundlePath) {
    Remove-Item $bundlePath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "      vm_bundles eliminata" -ForegroundColor Green
} else {
    Write-Host "      vm_bundles non presente" -ForegroundColor DarkGray
}

# ══════════════════════════════════════════════════
# STEP 5: Restart CoworkVMService
# ══════════════════════════════════════════════════
Write-Host "[5/6] Riavvio servizio CoworkVMService..." -ForegroundColor Yellow

$svc = Get-Service -Name "CoworkVMService" -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host "      [!] Servizio non trovato" -ForegroundColor Red
} else {
    try {
        Restart-Service -Name "CoworkVMService" -Force -ErrorAction Stop
    } catch {
        try {
            Start-Service -Name "CoworkVMService" -ErrorAction Stop
        } catch {
            sc.exe start CoworkVMService 2>$null | Out-Null
        }
    }

    Start-Sleep -Seconds 4
    $svcAfter = Get-Service -Name "CoworkVMService" -ErrorAction SilentlyContinue
    if ($svcAfter -and $svcAfter.Status -eq "Running") {
        Write-Host "      Servizio avviato" -ForegroundColor Green
    } else {
        $st = if ($svcAfter) { "$($svcAfter.Status)" } else { "sconosciuto" }
        Write-Host "      [!] Servizio in stato: $st" -ForegroundColor Red
    }
}

# ══════════════════════════════════════════════════
# STEP 6: Relaunch Claude Desktop
# ══════════════════════════════════════════════════
Write-Host "[6/6] Avvio Claude Desktop..." -ForegroundColor Yellow

$claudeExe = $null

# 1. Common install paths
$searchPaths = @(
    (Join-Path $env:LOCALAPPDATA "Programs\claude\Claude.exe"),
    (Join-Path $env:LOCALAPPDATA "claude\Claude.exe"),
    (Join-Path $env:LOCALAPPDATA "AnthropicClaude\Claude.exe"),
    (Join-Path $env:LOCALAPPDATA "Anthropic\Claude\Claude.exe"),
    (Join-Path $env:ProgramFiles "Claude\Claude.exe"),
    (Join-Path $env:ProgramFiles "Anthropic\Claude\Claude.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Claude\Claude.exe")
)
foreach ($p in $searchPaths) {
    if (Test-Path $p) { $claudeExe = $p; break }
}

# 2. Registry uninstall keys
if (-not $claudeExe) {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($rp in $regPaths) {
        $entry = Get-ItemProperty $rp -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "Claude" } | Select-Object -First 1
        if ($entry -and $entry.InstallLocation) {
            $candidate = Join-Path $entry.InstallLocation "Claude.exe"
            if (Test-Path $candidate) { $claudeExe = $candidate; break }
        }
    }
}

# 3. Start Menu shortcuts
if (-not $claudeExe) {
    $menuPaths = @(
        "$env:APPDATA\Microsoft\Windows\Start Menu",
        "$env:ProgramData\Microsoft\Windows\Start Menu"
    )
    foreach ($mp in $menuPaths) {
        $lnk = Get-ChildItem $mp -Recurse -Filter "Claude*.lnk" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($lnk) {
            $shell = New-Object -ComObject WScript.Shell
            $target = $shell.CreateShortcut($lnk.FullName).TargetPath
            if ($target -and (Test-Path $target)) { $claudeExe = $target; break }
        }
    }
}

# 4. Brute force scan LocalAppData
if (-not $claudeExe) {
    $found = Get-ChildItem $env:LOCALAPPDATA -Recurse -Filter "Claude.exe" -Depth 4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $claudeExe = $found.FullName }
}

if ($claudeExe) {
    Start-Process $claudeExe
    Write-Host "      Claude avviato: $claudeExe" -ForegroundColor Green
} else {
    Write-Host "      [!] Claude.exe non trovato. Avvia manualmente dal menu Start." -ForegroundColor Yellow
}

# ══════════════════════════════════════════════════
# DONE
# ══════════════════════════════════════════════════
Write-Host ""
Write-Host "  =========================================" -ForegroundColor Green
Write-Host "           OPERAZIONE COMPLETATA           " -ForegroundColor Green
Write-Host "  =========================================" -ForegroundColor Green
Write-Host ""

$fSvc = Get-Service -Name "CoworkVMService" -ErrorAction SilentlyContinue
$fProcs = @(Get-Process -Name "claude" -ErrorAction SilentlyContinue)
$svcColor = if ($fSvc -and $fSvc.Status -eq "Running") { "Green" } else { "Yellow" }
$svcText = if ($fSvc) { "$($fSvc.Status)" } else { "Non trovato" }

Write-Host "  Servizio VM:     $svcText" -ForegroundColor $svcColor
Write-Host "  Processi Claude: $($fProcs.Count) attivi" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Premi un tasto per chiudere..." -ForegroundColor DarkGray
[void][System.Console]::ReadKey($true)
