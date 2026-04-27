# build-win.ps1 — Windows PowerShell Magisk 模块打包
# 用法: 在 Windows 上双击运行或执行: powershell -ExecutionPolicy Bypass -File build-win.ps1

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$WORKDIR = $PSScriptRoot
$TMP = Join-Path $env:TEMP "usb_gps_switcher_build"
$OUT = Join-Path $WORKDIR "usb_gps_switcher.zip"

Write-Host "===== USB GPS Switcher — Magisk 模块打包 =====" -ForegroundColor Cyan
Write-Host "工作目录: $WORKDIR`n"

# 清理
if (Test-Path $TMP) { Remove-Item $TMP -Recurse -Force }
if (Test-Path $OUT) { Remove-Item $OUT -Force }

# 创建目录
$dirs = @(
    "$TMP",
    "$TMP\system\bin",
    "$TMP\system\etc",
    "$TMP\system\system\bin",
    "$TMP\system\system\etc\selinux"
)
foreach ($d in $dirs) { New-Item -ItemType Directory -Path $d -Force | Out-Null }

Write-Host "- 复制模块文件..." -ForegroundColor Yellow

# 核心文件
$files = @{
    "system\module.prop"          = "$TMP\module.prop"
    "system\service.sh"           = "$TMP\service.sh"
    "system\customize.sh"          = "$TMP\customize.sh"
    "system\system.prop"          = "$TMP\system\prop"
    "enable.sh"                   = "$TMP\enable.sh"
    "disable.sh"                  = "$TMP\disable.sh"
    "status.sh"                   = "$TMP\status.sh"
    "config.sh"                   = "$TMP\config.sh"
    "system\bin\usb_gps_bridge"   = "$TMP\system\bin\usb_gps_bridge"
    "system\bin\usb_gps_shell.sh" = "$TMP\system\bin\usb_gps_shell.sh"
    "system\system\bin\usb_gps_switcher_init.sh" = "$TMP\system\system\bin\usb_gps_switcher_init.sh"
    "system\system\etc\selinux\usb_gps_switcher.te" = "$TMP\system\system\etc\selinux\usb_gps_switcher.te"
}

foreach ($src in $files.Keys) {
    $dst = $files[$src]
    $srcFull = Join-Path $WORKDIR $src
    if (Test-Path $srcFull) {
        Copy-Item $srcFull $dst -Force
        Write-Host "  [OK] $src" -ForegroundColor Green
    } else {
        Write-Host "  [SKIP] $src (不存在)" -ForegroundColor DarkGray
    }
}

# 设置权限 (Unix 风格)
# 注意: Windows NTFS 不支持真正的 Unix 权限
# 这些在 Android 设备上会被重新解释

Write-Host "`n- 打包 zip..." -ForegroundColor Yellow

# 使用 .NET压缩
Add-Type -AssemblyName System.IO.Compression.FileSystem

# 手动创建 zip (兼容所有 Windows 版本)
# 不使用 Compress-Archive，因为它可能乱码

function Add-ZipEntry {
    param($zipPath, $srcPath, $entryName)
    
    if (-not (Test-Path $zipPath)) {
        # 创建空 zip
        Set-Content -Path $zipPath -Value (New-Object byte[] 0) -Encoding Byte
    }
    
    $tmpZip = $zipPath + ".tmp"
    Copy-Item $zipPath $tmpZip -Force
    
    # 用 SharpsZipLib 或 7z 如果有
    $7z = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($7z) {
        & 7z a -tzip "$zipPath" "$srcPath" -mx=9 | Out-Null
        if (Test-Path $tmpZip) { Remove-Item $tmpZip -Force }
    } else {
        # 用 PowerShell + ICSharpCode.SharpZipLib 或手动
        try {
            $fromZip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
            $toZip = [System.IO.Compression.ZipFile]::Open($tmpZip, "Update")
            
            # 复制已有条目
            foreach ($entry in $fromZip.Entries) {
                [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                    $toZip, $entry.FullName, $entry.CompressionLevel)
            }
            
            # 添加新条目
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $toZip, $srcPath, "Optimal")
            
            $fromZip.Dispose()
            $toZip.Dispose()
            
            Move-Item $tmpZip $zipPath -Force
        } catch {
            Write-Host "  [WARN] .NET压缩失败: $_" -ForegroundColor DarkYellow
            Write-Host "  请安装 7-Zip 并确保 7z.exe 在 PATH 中" -ForegroundColor Yellow
            if (Test-Path $tmpZip) { Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue }
            return
        }
    }
}

# 使用 Compress-Archive (PowerShell 5+)
# 先打包成普通zip再用ren改成.zip
$tmpArchive = Join-Path $env:TEMP "usb_gps_switcher_archive.zip"
if (Test-Path $tmpArchive) { Remove-Item $tmpArchive -Force }

try {
    Compress-Archive -Path "$TMP\*" -DestinationPath $tmpArchive -CompressionLevel Optimal -Force
    Move-Item $tmpArchive $OUT -Force
    Write-Host "  [OK] zip 打包完成" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] 打包失败: $_" -ForegroundColor Red
    Write-Host "  备选方案: 手动用 7-Zip 打包 $TMP 目录" -ForegroundColor Yellow
}

# 清理
Remove-Item $TMP -Recurse -Force -ErrorAction SilentlyContinue

if (Test-Path $OUT) {
    $size = (Get-Item $OUT).Length
    $sizeStr = if ($size -gt 1MB) { "{0:N1} MB" -f ($size/1MB) } else { "{0:N0} KB" -f ($size/1KB) }
    
    Write-Host "`n✅ 打包完成!" -ForegroundColor Green
    Write-Host "   输出: $OUT" -ForegroundColor White
    Write-Host "   大小: $sizeStr" -ForegroundColor White
    Write-Host ""
    Write-Host "下一步:" -ForegroundColor Cyan
    Write-Host "  1. 将 usb_gps_switcher.zip 复制到车机" -ForegroundColor White
    Write-Host "  2. Magisk App → 模块 → 从本地安装 → 选择zip" -ForegroundColor White
    Write-Host "  3. 重启车机" -ForegroundColor White
    Write-Host ""
    Write-Host "  重启后执行:" -ForegroundColor Cyan
    Write-Host "    sh /data/adb/usb_gps_switcher/enable.sh" -ForegroundColor White
} else {
    Write-Host "`n❌ 打包失败" -ForegroundColor Red
}
