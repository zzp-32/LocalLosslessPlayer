param([string]$OutputPath = "$PSScriptRoot\..\TestMedia\test-tone.wav")

$sampleRate = 44100
$seconds = 3
$channels = 1
$bits = 16
$samples = $sampleRate * $seconds
$dataSize = $samples * $channels * ($bits / 8)
$stream = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create)
$writer = [System.IO.BinaryWriter]::new($stream)
try {
    $writer.Write([Text.Encoding]::ASCII.GetBytes("RIFF")); $writer.Write([int32](36 + $dataSize)); $writer.Write([Text.Encoding]::ASCII.GetBytes("WAVE"))
    $writer.Write([Text.Encoding]::ASCII.GetBytes("fmt ")); $writer.Write([int32]16); $writer.Write([int16]1); $writer.Write([int16]$channels); $writer.Write([int32]$sampleRate); $writer.Write([int32]($sampleRate * $channels * ($bits / 8))); $writer.Write([int16]($channels * ($bits / 8))); $writer.Write([int16]$bits)
    $writer.Write([Text.Encoding]::ASCII.GetBytes("data")); $writer.Write([int32]$dataSize)
    for ($i = 0; $i -lt $samples; $i++) { $value = [int16](12000 * [Math]::Sin(2 * [Math]::PI * 440 * $i / $sampleRate)); $writer.Write($value) }
} finally { $writer.Dispose(); $stream.Dispose() }
Write-Output $OutputPath
