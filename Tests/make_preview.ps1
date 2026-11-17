param(
    [string]$ImageDirectory,
    [string]$OutputPath,
    [switch]$AllStyles,
    [switch]$WeatherPresets
)

# 本番AUF2が出力したPNGを市松背景へ合成する。素材やAI画像は使用しない。
$ErrorActionPreference = 'Stop'
if (-not $ImageDirectory) {
    $relativeImages = if ($WeatherPresets) { '..\Win64\Integrated\ReleaseImages' } else { '..\Win64\Stage1\ReleaseImages' }
    $ImageDirectory = Join-Path $PSScriptRoot $relativeImages
}
if (-not $OutputPath) {
    $relativeOutput = if ($WeatherPresets) { '..\Sample\weather_overview.png' } else { '..\Sample\stage1_overview.png' }
    $OutputPath = Join-Path $PSScriptRoot $relativeOutput
}
Add-Type -AssemblyName System.Drawing
$csvName = if ($WeatherPresets) { 'weather_presets.csv' } else { 'presets.csv' }
$rows = @(Import-Csv -LiteralPath (Join-Path $ImageDirectory $csvName) -Encoding utf8)
if (-not ($AllStyles -or $WeatherPresets)) { $rows = @($rows | Where-Object { [int]$_.style -in @(0,2,5,8,10,16,22,25,32,36,39,42) }) }
$columns = 4
$cellWidth = 320
$imageHeight = 180
$labelHeight = 28
$cellHeight = $imageHeight + $labelHeight
$height = [int][Math]::Ceiling($rows.Count / [double]$columns) * $cellHeight
$bitmap = [System.Drawing.Bitmap]::new($columns * $cellWidth, $height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$font = [System.Drawing.Font]::new('Yu Gothic UI', 11)
$labelBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(225,232,242))
$darkBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(20,28,43))
$lightBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(29,39,56))
try {
    $graphics.Clear([System.Drawing.Color]::FromArgb(12,18,29))
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    for ($index = 0; $index -lt $rows.Count; $index++) {
        $row = $rows[$index]
        $left = ($index % $columns) * $cellWidth
        $top = [int][Math]::Floor($index / [double]$columns) * $cellHeight
        for ($y = 0; $y -lt $imageHeight; $y += 20) {
            for ($x = 0; $x -lt $cellWidth; $x += 20) {
                $brush = if ((($x / 20 + $y / 20) % 2) -eq 0) { $darkBrush } else { $lightBrush }
                $graphics.FillRectangle($brush,$left+$x,$top+$y,20,20)
            }
        }
        $imageName = if ($WeatherPresets) { 'weather_{0:00}.png' -f [int]$row.style } else { '{0:00}.png' -f [int]$row.style }
        $image = [System.Drawing.Image]::FromFile((Join-Path $ImageDirectory $imageName))
        try { $graphics.DrawImage($image,[System.Drawing.Rectangle]::new($left,$top,$cellWidth,$imageHeight)) }
        finally { $image.Dispose() }
        $graphics.DrawString($row.name,$font,$labelBrush,[single]($left+10),[single]($top+$imageHeight+3))
    }
    $fullOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($fullOutputPath)) | Out-Null
    $bitmap.Save($fullOutputPath,[System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output $fullOutputPath
}
finally { $font.Dispose(); $labelBrush.Dispose(); $darkBrush.Dispose(); $lightBrush.Dispose(); $graphics.Dispose(); $bitmap.Dispose() }
