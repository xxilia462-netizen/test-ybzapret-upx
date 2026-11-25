#Requires -Version 5.1
[CmdletBinding()]
param (
    [int]$TimeoutMs = 3000,
    [int]$WarmupSec = 2,
    [switch]$ExportReport
)

$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "ybzapret-upx | Deep DPI & Socket Benchmark Engine"

function Test-AdminPrivileges {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-AdminPrivileges)) {
    Write-Host "[CRITICAL] Administrator privileges are required." -ForegroundColor Red
    Pause
    exit 1
}

$BaseDir       = (Resolve-Path "$PSScriptRoot\..").Path
$BinPath       = Join-Path $BaseDir "bin\winws.exe"
$StrategiesBat = Join-Path $BaseDir "utils\strategies.bat"
$TargetsFile   = Join-Path $PSScriptRoot "targets.txt"
$ReportFile    = Join-Path $BaseDir "benchmark_report.log"

if (-not (Test-Path $BinPath)) {
    Write-Host "[ERROR] Engine binary missing: $BinPath" -ForegroundColor Red
    Pause
    exit 1
}

function Get-BenchmarkTargets {
    param([string]$Path)

    $defaultTargets = @(
        "https://youtube.com",
        "https://ytimg.com",
        "https://googlevideo.com",
        "https://discord.com",
        "https://discord.gg",
        "https://discordapp.com",
        "https://github.com",
        "https://telegram.org"
    )

    $rawList = if (Test-Path $Path) {
        Get-Content -Path $Path | Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") }
    } else {
        $defaultTargets
    }

    $parsedTargets = @()
    foreach ($entry in $rawList) {
        $clean = $entry.Trim()
        if ($clean -notmatch "^https?://") { $clean = "https://$clean" }
        try {
            $uri = [System.Uri]$clean
            $parsedTargets += [PSCustomObject]@{
                RawUrl = $clean
                Host   = $uri.Host
                Port   = if ($uri.Port -gt 0) { $uri.Port } else { 443 }
                Path   = $uri.PathAndQuery
            }
        } catch {
            Write-Host "[WARN] Skipping malformed target: $entry" -ForegroundColor DarkYellow
        }
    }
    return $parsedTargets
}

function Get-ParsedStrategies {
    param([string]$BatPath)

    $extracted = @()
    if (Test-Path $BatPath) {
        $lines = Get-Content -Path $BatPath
        foreach ($line in $lines) {
            if ($line -match 'if\s+"%strat%"=="(\d+)"\s+set\s+"ARGS=(.+?)"\s+&') {
                $id   = $Matches
                $args = $Matches

                $args = $args.Replace('\"', '"')
                $args = $args.Replace('%LIST%',      "$BaseDir\lists\blacklist.txt")
                $args = $args.Replace('%IPSET%',     "$BaseDir\lists\ipset-all.txt")
                $args = $args.Replace('%FAKE_TLS%',  "$BaseDir\bin\tls_clienthello_www_google_com.bin")
                $args = $args.Replace('%FAKE_QUIC%', "$BaseDir\bin\quic_initial_www_google_com.bin")

                $label = if ($id -eq "10") { "FAKE ONLY" } else { "ALT $id" }
                $extracted += [PSCustomObject]@{
                    Id        = [int]$id
                    Name      = $label
                    Arguments = $args
                }
            }
        }
    }

    if ($extracted.Count -eq 0) {
        $extracted += [PSCustomObject]@{
            Id        = 9
            Name      = "ALT 9 (Fallback)"
            Arguments = "--wf-tcp=80,443 --wf-udp=443 --filter-tcp=443 --hostlist=`"$BaseDir\lists\blacklist.txt`" --dpi-desync=fake,multisplit --dpi-desync-split-seqovl=2 --dpi-desync-fooling=badseq"
        }
    }
    return $extracted | Sort-Object Id
}

function Invoke-DeepSocketProbe {
    param (
        [string]$TargetHost,
        [int]$Port = 443,
        [int]$Timeout = 3000
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $result = [PSCustomObject]@{
        Success    = $false
        TcpOk      = $false
        TlsOk      = $false
        LatencyMs  = 0
        Protocol   = "None"
        ErrorStage = ""
    }

    try {
        $connectTask = $tcpClient.ConnectAsync($TargetHost, $Port)
        if (-not $connectTask.Wait($Timeout)) {
            $result.ErrorStage = "TCP_TIMEOUT"
            return $result
        }
        if (-not $tcpClient.Connected) {
            $result.ErrorStage = "TCP_REFUSED"
            return $result
        }
        $result.TcpOk = $true

        $netStream = $tcpClient.GetStream()
        $netStream.ReadTimeout  = $Timeout
        $netStream.WriteTimeout = $Timeout

        $sslStream = New-Object System.Net.Security.SslStream($netStream, $false, ({ $true }))
        $authTask = $sslStream.AuthenticateAsClientAsync($TargetHost)

        if (-not $authTask.Wait($Timeout)) {
            $result.ErrorStage = "DPI_TLS_DROP"
            return $result
        }

        $sw.Stop()
        $result.TlsOk     = $true
        $result.Success   = $true
        $result.LatencyMs = $sw.ElapsedMilliseconds
        $result.Protocol  = $sslStream.SslProtocol.ToString()
    } catch {
        $sw.Stop()
        $result.ErrorStage = if ($result.TcpOk) { "DPI_RST_INJECT" } else { "NET_UNREACHABLE" }
    } finally {
        if ($sslStream) { $sslStream.Dispose() }
        if ($tcpClient) { $tcpClient.Close() }
    }

    return $result
}

function Stop-BypassEngine {
    Get-Process -Name "winws" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 400
}

function Start-BypassEngine {
    param([string]$Arguments)
    Stop-BypassEngine
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $BinPath
    $psi.Arguments = $Arguments
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $true
    return [System.Diagnostics.Process]::Start($psi)
}

Clear-Host
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "          ybzapret-upx | Deep DPI & TLS Socket Benchmark             " -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan

$targets    = Get-BenchmarkTargets -Path $TargetsFile
$strategies = Get-ParsedStrategies -BatPath $StrategiesBat

Write-Host "[*] Loaded Targets    : $($targets.Count)" -ForegroundColor Gray
Write-Host "[*] Loaded Strategies : $($strategies.Count)" -ForegroundColor Gray
Write-Host ""

Stop-BypassEngine
Write-Host ">>> Running BASELINE check (No Bypass Active)..." -ForegroundColor DarkYellow
$basePassed = 0
foreach ($t in $targets) {
    $probe = Invoke-DeepSocketProbe -TargetHost $t.Host -Port $t.Port -Timeout $TimeoutMs
    if ($probe.Success) { $basePassed++ }
}
Write-Host "    Baseline score: $basePassed / $($targets.Count) reachable without bypass." -ForegroundColor DarkYellow
Write-Host ""

$summaryMatrix = @()

foreach ($strat in $strategies) {
    Write-Host "---------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "Testing [$($strat.Name)]..." -ForegroundColor Cyan

    $proc = Start-BypassEngine -Arguments $strat.Arguments
    Start-Sleep -Seconds $WarmupSec

    $passedCount = 0
    $latencySum  = 0
    $dpiDrops    = 0

    foreach ($t in $targets) {
        $probe = Invoke-DeepSocketProbe -TargetHost $t.Host -Port $t.Port -Timeout $TimeoutMs
        $hostPadded = $t.Host.PadRight(28)

        if ($probe.Success) {
            $passedCount++
            $latencySum += $probe.LatencyMs
            Write-Host "  [PASS] $hostPadded | $($probe.Protocol.PadRight(6)) | $($probe.LatencyMs) ms" -ForegroundColor Green
        } else {
            if ($probe.ErrorStage -like "DPI_*") { $dpiDrops++ }
            Write-Host "  [FAIL] $hostPadded | Stage: $($probe.ErrorStage)" -ForegroundColor Red
        }
    }

    $avgMs = if ($passedCount -gt 0) { [math]::Round($latencySum / $passedCount) } else { 9999 }
    $rate  = [math]::Round(($passedCount / $targets.Count) * 100)

    $summaryMatrix += [PSCustomObject]@{
        Strategy  = $strat.Name
        Score     = "$passedCount/$($targets.Count) ($rate%)"
        RawPassed = $passedCount
        DpiBlocks = $dpiDrops
        AvgTLS_ms = if ($avgMs -eq 9999) { "TIMEOUT" } else { "$avgMs ms" }
        RawMs     = $avgMs
    }
}

Stop-BypassEngine

Clear-Host
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "                  FINAL BENCHMARK LEADERBOARD                        " -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan

$ranked = $summaryMatrix | Sort-Object -Property @{Expression="RawPassed";Descending=$true}, @{Expression="RawMs";Ascending=$true}
$ranked | Format-Table Strategy, Score, DpiBlocks, AvgTLS_ms -AutoSize

$best = $ranked | Select-Object -First 1
if ($best.RawPassed -gt 0) {
    Write-Host "[RECOMMENDED] Best strategy: $($best.Strategy) ($($best.Score), Avg TLS: $($best.AvgTLS_ms))" -ForegroundColor Green
} else {
    Write-Host "[WARNING] No strategy passed. Check winws.exe or WinDivert." -ForegroundColor Red
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"ybzapret-upx Benchmark Report ($timestamp)" | Out-File -FilePath $ReportFile -Encoding UTF8
$ranked | Format-Table Strategy, Score, DpiBlocks, AvgTLS_ms -AutoSize | Out-File -FilePath $ReportFile -Append -Encoding UTF8
Write-Host ""
Write-Host "[*] Detailed report saved to: $ReportFile" -ForegroundColor DarkGray

Pause
