# Writes the macOS app icons (16 to 1024 px) into the asset catalog of the runner. Windows only, it uses GDI+:
#   powershell -ExecutionPolicy Bypass -File macos\packaging\make_app_icon.ps1
param([string]$OutDir = (Join-Path $PSScriptRoot '..\Runner\Assets.xcassets\AppIcon.appiconset'))
Add-Type -AssemblyName System.Drawing
$OutDir = (Resolve-Path $OutDir).Path

# Draws the MQTT Studio icon in the macOS layout: a white rounded square (824 of 1024, corner radius 185) with a soft
# shadow and the three bars of CI/MQTT-Logo-03.png, measured in its pixels.
function RoundedRect([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = 2 * $r
  $p.AddArc($x, $y, $d, $d, 180, 90)
  $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  return $p
}

function Draw-Icon([int]$size, [string]$path) {
  $f = $size / 1024.0
  $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.PixelOffsetMode = 'HighQuality'
  $g.CompositingQuality = 'HighQuality'
  $g.Clear([System.Drawing.Color]::Transparent)

  # shadow below the body, layered rounded squares fading out
  if ($size -ge 64) {
    for ($i = 12; $i -ge 1; $i--) {
      $grow = $i * 1.5 * $f
      $shadow = RoundedRect (100 * $f - $grow) (100 * $f - $grow + 12 * $f) (824 * $f + 2 * $grow) (824 * $f + 2 * $grow) (185 * $f + $grow)
      $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(6, 0, 0, 0))
      $g.FillPath($brush, $shadow)
      $brush.Dispose(); $shadow.Dispose()
    }
  }

  $body = RoundedRect (100 * $f) (100 * $f) (824 * $f) (824 * $f) (185 * $f)
  $rect = New-Object System.Drawing.RectangleF (100 * $f), (100 * $f), (824 * $f), (824 * $f)
  $fill = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.Color]::FromArgb(255, 255, 255, 255)), ([System.Drawing.Color]::FromArgb(255, 238, 238, 238)), 90.0
  $g.FillPath($fill, $body)
  $fill.Dispose()
  if ($size -ge 64) {
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(30, 0, 0, 0)), ([single][Math]::Max(1, 2 * $f))
    $g.DrawPath($pen, $body)
    $pen.Dispose()
  }
  $body.Dispose()

  # bars in logo pixels: x, top, bottom; width 185; the logo spans 780 x 984 (y 9 to 993)
  $bars = @(@(0, 326, 654), @(297, 9, 993), @(595, 174, 821))
  $glyphHeight = 500.0
  $scale = $glyphHeight / 984.0
  $originX = 512 - 780 * $scale / 2
  $originY = 512 - $glyphHeight / 2 - 9 * $scale
  $red = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 0x9B, 0x00, 0x1E))
  foreach ($bar in $bars) {
    $w = 185 * $scale * $f
    $x = ($originX + $bar[0] * $scale) * $f
    $y = ($originY + $bar[1] * $scale) * $f
    $h = ($bar[2] - $bar[1]) * $scale * $f
    $capsule = RoundedRect $x $y $w $h ($w / 2)
    $g.FillPath($red, $capsule)
    $capsule.Dispose()
  }
  $red.Dispose()
  $g.Dispose()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

foreach ($size in 16, 32, 64, 128, 256, 512, 1024) {
  Draw-Icon $size (Join-Path $OutDir "app_icon_$size.png")
}
