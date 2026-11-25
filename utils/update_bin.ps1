$Host.UI.RawUI.WindowTitle = "ybzapret-upx - Binaries Updater"

$BaseDir = Resolve-Path "$PSScriptRoot\.."
$BinDir = Join-Path $BaseDir "bin"
$TempZip = Join-Path $env:TEMP "zapret-win-bundle.zip"
$TempExtract = Join-Path $env:TEMP "zapret-extract"
$BundleUrl = "https://github.com"

if (-not (Test-Path $BinDir)) { New-Item -ItemType Directory -Path $BinDir -Force | Out-Null }

try {
    Write-Host "[1/3] Downloading winws.exe, drivers and .bin payloads..." -ForegroundColor Yellow
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $BundleUrl -OutFile $TempZip -UseBasicParsing

    Write-Host "[2/3] Extracting to bin\..." -ForegroundColor Yellow
    if (Test-Path $TempExtract) { Remove-Item $TempExtract -Recurse -Force }
    Expand-Archive -Path $TempZip -DestinationPath $TempExtract -Force

    $WinwsFolder = Get-ChildItem -Path $TempExtract -Recurse -Filter "winws.exe" | Select-Object -First 1 -ExpandProperty DirectoryName
    if ($WinwsFolder) { Copy-Item -Path "$WinwsFolder\*" -Destination $BinDir -Force }

    Get-ChildItem -Path $TempExtract -Recurse -Filter "*.bin" | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $BinDir -Force
    }

    Write-Host "[3/3] Cleaning up..." -ForegroundColor Yellow
    Remove-Item $TempZip, $TempExtract -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] Done! Folder bin\ is ready." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
}
Pause
