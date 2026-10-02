<#
    Gerar-Icone.ps1
    Gera instalador\icone.ico (atalhos e setup) com System.Drawing: fundo
    grafite arredondado, corpo de camera branco e lente no acento do painel.
    PNG dentro do ICO (16, 24, 32, 48, 64, 128, 256): o Windows 10/11 le.
    Rodar uma vez e commitar o .ico; nao faz parte do build.

    Uso:
        .\Gerar-Icone.ps1
#>
[CmdletBinding()]
param([string]$Saida = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Saida)) {
    $aqui = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($aqui)) { $aqui = Split-Path -Parent $MyInvocation.MyCommand.Path }
    $Saida = Join-Path $aqui 'icone.ico'
}
Add-Type -AssemblyName System.Drawing

function New-Png {
    param([int]$Tam, [System.Collections.Generic.List[byte[]]]$Destino)
    $bmp = New-Object Drawing.Bitmap($Tam, $Tam, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.Clear([Drawing.Color]::Transparent)
        $s = $Tam / 64.0   # desenhado numa grade de 64

        # Fundo: quadrado arredondado grafite.
        $fundo = New-Object Drawing.Drawing2D.GraphicsPath
        $r = 14 * $s; $d = $r * 2; $w = $Tam - 1
        $fundo.AddArc(0, 0, $d, $d, 180, 90); $fundo.AddArc($w - $d, 0, $d, $d, 270, 90)
        $fundo.AddArc($w - $d, $w - $d, $d, $d, 0, 90); $fundo.AddArc(0, $w - $d, $d, $d, 90, 90)
        $fundo.CloseFigure()
        $g.FillPath((New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, 43, 47, 54))), $fundo)

        # Corpo da camera (branco) com "capuz" em cima.
        $branco = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, 245, 246, 248))
        $corpo = New-Object Drawing.Drawing2D.GraphicsPath
        $x = 10 * $s; $y = 22 * $s; $cw = 44 * $s; $ch = 28 * $s; $cr = 5 * $s
        $corpo.AddArc($x, $y, $cr * 2, $cr * 2, 180, 90); $corpo.AddArc($x + $cw - $cr * 2, $y, $cr * 2, $cr * 2, 270, 90)
        $corpo.AddArc($x + $cw - $cr * 2, $y + $ch - $cr * 2, $cr * 2, $cr * 2, 0, 90); $corpo.AddArc($x, $y + $ch - $cr * 2, $cr * 2, $cr * 2, 90, 90)
        $corpo.CloseFigure()
        $g.FillPath($branco, $corpo)
        $g.FillRectangle($branco, [single](22 * $s), [single](16 * $s), [single](16 * $s), [single](8 * $s))

        # Lente: anel grafite e miolo no acento.
        $g.FillEllipse((New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, 43, 47, 54))), [single](22 * $s), [single](26 * $s), [single](20 * $s), [single](20 * $s))
        $g.FillEllipse((New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, 47, 128, 237))), [single](26 * $s), [single](30 * $s), [single](12 * $s), [single](12 * $s))
        # Brilho.
        $g.FillEllipse($branco, [single](28 * $s), [single](32 * $s), [single](3 * $s), [single](3 * $s))
    } finally { $g.Dispose() }
    $ms = New-Object IO.MemoryStream
    $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    # Lista tipada: devolver byte[] direto desembrulha os bytes no pipeline.
    $Destino.Add($ms.ToArray())
}

$tamanhos = @(16, 24, 32, 48, 64, 128, 256)
$pngs = New-Object 'System.Collections.Generic.List[byte[]]'
foreach ($t in $tamanhos) { New-Png -Tam $t -Destino $pngs }

# ICO: ICONDIR (6) + ICONDIRENTRY (16 x N) + imagens.
$ms = New-Object IO.MemoryStream
$bw = New-Object IO.BinaryWriter($ms)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$tamanhos.Count)
$offset = 6 + 16 * $tamanhos.Count
for ($i = 0; $i -lt $tamanhos.Count; $i++) {
    $t = $tamanhos[$i]
    $bw.Write([byte]$(if ($t -ge 256) { 0 } else { $t }))   # largura (0 = 256)
    $bw.Write([byte]$(if ($t -ge 256) { 0 } else { $t }))   # altura
    $bw.Write([byte]0); $bw.Write([byte]0)                   # cores, reservado
    $bw.Write([uint16]1); $bw.Write([uint16]32)              # planos, bits
    $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$offset)
    $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $bw.Write([byte[]]$p) }
$bw.Flush()
[IO.File]::WriteAllBytes($Saida, $ms.ToArray())
Write-Host ("icone gravado: " + $Saida + " (" + [math]::Round($ms.Length / 1KB) + " KB, " + $tamanhos.Count + " tamanhos)") -ForegroundColor Green
