param(
    [string]$ImageDirectory = (Join-Path $PSScriptRoot '..\Win64\CloudFlow\Frames'),
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\Sample\cloud_flow.gif')
)

# 本番AUF2の連番PNGを縮小してGIFへまとめる。形・色の補正や補間フレームは追加しない。
# フレームごとのパレットを保持し、初期状態の約12秒間を5fpsでループする。
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$frames = @(Get-ChildItem -LiteralPath $ImageDirectory -Filter 'flow_*.png' | Sort-Object Name)
if ($frames.Count -eq 0) { throw 'No production cloud frames found.' }
$fullOutput = [IO.Path]::GetFullPath($OutputPath)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($fullOutput)) | Out-Null
$writer = [IO.BinaryWriter]::new([IO.File]::Create($fullOutput))
try {
    $writer.Write([Text.Encoding]::ASCII.GetBytes('GIF89a'))
    $writer.Write([UInt16]640); $writer.Write([UInt16]360)
    $writer.Write([byte[]]@(0,0,0))
    $writer.Write([byte[]]@(0x21,0xFF,11))
    $writer.Write([Text.Encoding]::ASCII.GetBytes('NETSCAPE2.0'))
    $writer.Write([byte[]]@(3,1,0,0,0))
    foreach ($frame in $frames) {
        $source = [Drawing.Image]::FromFile($frame.FullName)
        $bitmap = [Drawing.Bitmap]::new(640,360)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        $memory = [IO.MemoryStream]::new()
        try {
            $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.DrawImage($source,[Drawing.Rectangle]::new(0,0,640,360))
            $bitmap.Save($memory,[Drawing.Imaging.ImageFormat]::Gif)
            $frameBytes = $memory.ToArray()
        }
        finally { $memory.Dispose(); $graphics.Dispose(); $bitmap.Dispose(); $source.Dispose() }
        $globalFlags = $frameBytes[10]
        $paletteSize = if ($globalFlags -band 128) { 3 * [int][Math]::Pow(2,($globalFlags -band 7)+1) } else { 0 }
        [byte[]]$palette = if ($paletteSize) { [byte[]]$frameBytes[13..(12+$paletteSize)] } else { [byte[]]@() }
        $position = 13 + $paletteSize
        while ($frameBytes[$position] -eq 0x21) {
            $position += 2
            do { $blockSize=$frameBytes[$position]; $position+=1+$blockSize } while ($blockSize)
        }
        if ($frameBytes[$position] -ne 0x2C) { throw 'Unexpected GIF frame structure.' }
        $position++
        $descriptor = [byte[]]$frameBytes[$position..($position+8)]
        $position += 9
        if ($descriptor[8] -band 128) {
            $paletteSize = 3 * [int][Math]::Pow(2,($descriptor[8] -band 7)+1)
            $palette = [byte[]]$frameBytes[$position..($position+$paletteSize-1)]
            $position += $paletteSize
        }
        else { $descriptor[8] = ($descriptor[8] -band 0x40) -bor 128 -bor ($globalFlags -band 7) }
        if (-not $palette.Length) { throw 'Missing GIF palette.' }
        $writer.Write([byte[]]@(0x21,0xF9,4,4,20,0,0,0))
        $writer.Write([byte]0x2C); $writer.Write([byte[]]$descriptor); $writer.Write([byte[]]$palette)
        $writer.Write([byte]$frameBytes[$position]); $position++
        do {
            $blockSize=$frameBytes[$position]; $position++
            $writer.Write([byte]$blockSize)
            if ($blockSize) { $writer.Write($frameBytes,$position,[int]$blockSize); $position+=$blockSize }
        } while ($blockSize)
    }
    $writer.Write([byte]0x3B)
}
finally { $writer.Dispose() }
$result = [Drawing.Image]::FromFile($fullOutput)
try {
    $count = $result.GetFrameCount([Drawing.Imaging.FrameDimension]::Time)
    if ($count -ne $frames.Count) { throw 'GIF frame count mismatch.' }
    [pscustomobject]@{Path=$fullOutput;Frames=$count;Seconds=$count*0.2;Bytes=(Get-Item -LiteralPath $fullOutput).Length}
}
finally { $result.Dispose() }
