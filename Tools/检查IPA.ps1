# 检查IPA.ps1 —— 把 .ipa 拖进 bat 时实际干活的那一层
# 作用：找到本机任意一个可用的 Python，然后调用同目录的 ipa_check.py

param(
    [Parameter(Mandatory = $false)][string]$Ipa,
    [string]$Udid,
    [string]$IosVersion,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

function Find-Python {
    $cands = @()
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) { $cands += $cmd.Source }

    # 豆包运行时自带的 Python（这台机器上常见的唯一一个）
    $glob1 = Join-Path $env:LOCALAPPDATA 'Doubao\User Data\sandbox_runtime\bases\*\python\python.exe'
    $cands += @(Get-ChildItem -Path $glob1 -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -ExpandProperty FullName)

    # 常规安装位置
    $glob2 = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python*\python.exe'
    $cands += @(Get-ChildItem -Path $glob2 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    $glob3 = 'C:\Python3*\python.exe'
    $cands += @(Get-ChildItem -Path $glob3 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)

    foreach ($c in $cands) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

if (-not $Ipa) {
    Write-Host '没有传 IPA 路径。用法：检查IPA.bat "C:\某目录\某.ipa"' -ForegroundColor Yellow
    exit 1
}
if (-not (Test-Path -LiteralPath $Ipa)) {
    Write-Host ("找不到文件：{0}" -f $Ipa) -ForegroundColor Red
    exit 1
}

$py = Find-Python
if (-not $py) {
    Write-Host '本机没找到 Python。装一个（https://www.python.org/downloads/）再回来跑这个脚本。' -ForegroundColor Red
    exit 1
}

$script = Join-Path $PSScriptRoot 'ipa_check.py'
$argv = @($script, $Ipa)
if ($Udid)       { $argv += @('--udid', $Udid) }
if ($IosVersion) { $argv += @('--ios-version', $IosVersion) }
if ($Json)       { $argv += '--json' }

& $py @argv
exit $LASTEXITCODE
