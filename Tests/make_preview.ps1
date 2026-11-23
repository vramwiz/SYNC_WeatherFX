param(
    [string]$ImageDirectory,
    [string]$OutputPath,
    [switch]$WeatherPresets # 従来のプリセット一覧の呼び出しと互換。
)

# 本番AUF2が出力したPNGを市松背景へ合成する。素材やAI画像は使用しない。
$ErrorActionPreference = 'Stop'
if (-not $ImageDirectory) { $ImageDirectory = Join-Path $PSScriptRoot '..\Win64\Verification\Images' }
if (-not $OutputPath) { $OutputPath = Join-Path $PSScriptRoot '..\Sample\weather_overview.png' }
Add-Type -AssemblyName System.Drawing
$rows = @(Import-Csv -LiteralPath (Join-Path $ImageDirectory 'weather_presets.csv') -Encoding utf8)
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
        $imageName = 'weather_{0:00}.png' -f [int]$row.style
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
