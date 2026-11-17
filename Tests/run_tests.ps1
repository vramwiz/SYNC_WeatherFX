param(
    [string]$PluginPath = 'C:\ProgramData\aviutl2\Plugin\SYNC_WeatherFX\SYNC_WeatherFX.auf2',
    [string]$ImageDirectory,
    [switch]$Benchmark,
    [switch]$DefaultPreview,
    [switch]$CloudFlowPreview,
    [switch]$Profile
)

# 本番AUF2を検査EXEから読み込む。別プラグインやホストアプリは起動しない。
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $projectDirectory 'Win64\Verification'
$dcuDirectory = Join-Path $outputDirectory 'DCU'
if (-not $ImageDirectory) { $ImageDirectory = Join-Path $outputDirectory 'Images' }
$ImageDirectory = [System.IO.Path]::GetFullPath($ImageDirectory)
New-Item -ItemType Directory -Path $dcuDirectory -Force | Out-Null
$compiler = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$libraryDirectory = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\lib\Win64\release'
Push-Location $PSScriptRoot
try {
    & $compiler '--no-config' '-B' '-Q' '-TX.exe' '-$R+' '-$Q+' '-NSSystem;Winapi;Vcl' `
        "-U$libraryDirectory;$libraryDirectory\JA" "-E$outputDirectory" "-NU$dcuDirectory" 'WeatherFX_RenderTests.dpr'
    if ($LASTEXITCODE -ne 0) { throw 'Weather verification build failed.' }
    $testArguments = @($PluginPath, $ImageDirectory)
    if ($Benchmark) { $testArguments += '--benchmark' }
    elseif ($DefaultPreview) { $testArguments += '--preview-default' }
    elseif ($CloudFlowPreview) { $testArguments += '--preview-flow' }
    elseif ($Profile) { $testArguments += '--profile' }
    & (Join-Path $outputDirectory 'WeatherFX_RenderTests.exe') @testArguments
    if ($LASTEXITCODE -ne 0) { throw 'Production AUF2 verification failed.' }
}
finally { Pop-Location }
