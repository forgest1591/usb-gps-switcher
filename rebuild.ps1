$ErrorActionPreference = "SilentlyContinue"
$WORKDIR = "C:\Users\admin\.qclaw\workspace\android13-usb-gps-switcher"
$TMP = "$env:TEMP\usb_gps_v3"
$OUT = "$WORKDIR\usb_gps_switcher.zip"

Remove-Item $TMP -Recurse -Force 2>$null
Remove-Item $OUT -Force 2>$null

# Create temp dirs
@("$TMP","$TMP\system","$TMP\system\bin") | ForEach-Object {
    New-Item -ItemType Directory -Path $_ -Force | Out-Null
}

# File mapping
$files = @{
    "system\module.prop"               = "$TMP\module.prop"
    "system\service.sh"                = "$TMP\service.sh"
    "system\customize.sh"              = "$TMP\customize.sh"
    "system\system.prop"               = "$TMP\system.prop"
    "enable.sh"                       = "$TMP\enable.sh"
    "disable.sh"                       = "$TMP\disable.sh"
    "status.sh"                        = "$TMP\status.sh"
    "config.sh"                        = "$TMP\config.sh"
    "system\bin\usb_gps_bridge"        = "$TMP\system\bin\usb_gps_bridge"
    "system\bin\usb_gps_shell.sh"      = "$TMP\system\bin\usb_gps_shell.sh"
    "system\bin\usb_gps_switcher_init.sh" = "$TMP\system\bin\usb_gps_switcher_init.sh"
}

$ok = 0; $skip = 0
foreach ($src in $files.Keys) {
    $dst = $files[$src]
    $srcFull = Join-Path $WORKDIR $src
    if (Test-Path $srcFull) {
        Copy-Item $srcFull $dst -Force
        $ok++
        Write-Host "[OK] $src"
    } else {
        $skip++
        Write-Host "[SKIP] $src"
    }
}

# Set executable
if (Test-Path "$TMP\system\bin\usb_gps_bridge") {
    # Binary is already executable on Linux, no chmod needed in zip
}

# Build zip
Compress-Archive -Path "$TMP\*" -DestinationPath $OUT -CompressionLevel Optimal -Force
Remove-Item $TMP -Recurse -Force

if (Test-Path $OUT) {
    $size = (Get-Item $OUT).Length
    $sizeStr = if ($size -gt 1MB) { "{0:N1} MB" -f ($size/1MB) } else { "{0:N0} KB" -f ($size/1KB) }
    Write-Host ""
    Write-Host "========================================"
    Write-Host "  DONE! 打包了 $ok 个文件, 跳过 $skip 个"
    Write-Host "  输出: $OUT"
    Write-Host "  大小: $sizeStr"
    Write-Host "========================================"

    # Verify binary
    $bin = "$WORKDIR\system\bin\usb_gps_bridge"
    if (Test-Path $bin) {
        $bsize = (Get-Item $bin).Length
        Write-Host "  ARM64 二进制: $([math]::Round($bsize/1KB, 1)) KB"
    }
} else {
    Write-Host "打包失败!"
}
