$NDK = "C:\Users\admin\AppData\Local\Android\Sdk\ndk\30.0.14904198"
$CLANG = "$NDK\toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android21-clang++"
$SRC = "C:\Users\admin\.qclaw\workspace\android13-usb-gps-switcher\main.cpp"
$OUT = "C:\Users\admin\.qclaw\workspace\android13-usb-gps-switcher\system\bin\usb_gps_bridge"

Write-Host "=== Compiling ARM64 binary ==="
Write-Host "Compiler: $CLANG"

$cmd = """$CLANG"" -target aarch64-linux-android21 -static -std=c++17 -O2 -fno-exceptions -fno-rtti -DNDEBUG `"$SRC`" -o `"$OUT`""
Write-Host "CMD: $cmd"

$output = & cmd /c $cmd 2>&1
$output | Write-Host

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "SUCCESS!"
    $size = (Get-Item $OUT).Length
    Write-Host "Binary size: $([math]::Round($size)) bytes ($( [math]::Round($size/1KB, 1)) KB)"
} else {
    Write-Host "FAILED exit=$LASTEXITCODE"
}
