$Host.UI.RawUI.WindowTitle = "ybzapret-upx - Apply Hosts"

$BaseDir = Resolve-Path "$PSScriptRoot\.."
$SourceHosts = Join-Path $BaseDir ".service\hosts"
$SystemHosts = "$env:SystemRoot\System32\drivers\etc\hosts"
$BackupHosts = "$env:SystemRoot\System32\drivers\etc\hosts.ybzapret.bak"

if (-not (Test-Path $SourceHosts)) {
    Write-Host "[ERROR] .service\hosts file not found!" -ForegroundColor Red
    Pause
    exit
}

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "    ybzapret-upx - Updating System Hosts " -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

try {
    # Create backup of original Windows hosts file if not exists
    if (-not (Test-Path $BackupHosts)) {
        Copy-Item -Path $SystemHosts -Destination $BackupHosts -Force
        Write-Host "[OK] Backup saved to hosts.ybzapret.bak" -ForegroundColor Green
    }

    $currentContent = Get-Content -Path $SystemHosts -Raw -ErrorAction SilentlyContinue
    $newEntries = Get-Content -Path $SourceHosts -Raw

    if ($currentContent -match "# ybzapret-upx hosts start") {
        Write-Host "[INFO] ybzapret-upx entries are already present in system hosts." -ForegroundColor Yellow
    } else {
        $block = "`r`n`r`n# ybzapret-upx hosts start`r`n$newEntries`r`n# ybzapret-upx hosts end`r`n"
        Add-Content -Path $SystemHosts -Value $block -Encoding ASCII
        ipconfig /flushdns | Out-Null
        Write-Host "[OK] Hosts successfully updated and DNS cache flushed!" -ForegroundColor Green
    }
} catch {
    Write-Host "[ERROR] Run as Administrator! $($_.Exception.Message)" -ForegroundColor Red
}

Pause
