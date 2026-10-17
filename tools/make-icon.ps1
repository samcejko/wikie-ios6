param(
    [string]$OutFile = "Resources\icon_wikie.png",
    [int]$Size = 512,
    [string]$Theme = "Slate"
)

Add-Type -AssemblyName System.Drawing

$bmp = New-Object System.Drawing.Bitmap $Size, $Size
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

# 1. Rounded rectangle mask (iOS 6 squircle)
$radius = [int]($Size * 0.22)
$dia = $radius * 2
$iconPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$iconPath.AddArc(0, 0, $dia, $dia, 180, 90)
$iconPath.AddArc($Size - $dia, 0, $dia, $dia, 270, 90)
$iconPath.AddArc($Size - $dia, $Size - $dia, $dia, $dia, 0, 90)
$iconPath.AddArc(0, $Size - $dia, $dia, $dia, 90, 90)
$iconPath.CloseFigure()

$g.SetClip($iconPath)

# 2. Background gradient
$rect = New-Object System.Drawing.Rectangle 0, 0, $Size, $Size
if ($Theme -eq "Blue") {
    $cTop = [System.Drawing.Color]::FromArgb(255, 30, 80, 160)
    $cBot = [System.Drawing.Color]::FromArgb(255, 10, 30, 70)
} else {
    $cTop = [System.Drawing.Color]::FromArgb(255, 38, 48, 64)
    $cBot = [System.Drawing.Color]::FromArgb(255, 12, 17, 24)
}
$bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush ($rect, $cTop, $cBot, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
$g.FillRectangle($bgBrush, $rect)
$bgBrush.Dispose()

# Top rim highlight (like in all user's icons)
$rimBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(60, 255, 255, 255))
$g.FillRectangle($rimBrush, 0, 0, $Size, [int]($Size * 0.008))
$rimBrush.Dispose()

# 3. Center Globe Medallion
$center = [int]($Size / 2)
$centerY = [int]($Size * 0.52)
$globeR = [int]($Size * 0.33)

# Shadow behind globe
for ($s = 12; $s -gt 0; $s--) {
    $alpha = [int](18 - $s)
    if ($alpha -lt 1) { $alpha = 1 }
    $sBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($alpha, 0, 0, 0))
    $g.FillEllipse($sBrush, ($center - $globeR - $s), ($centerY - $globeR + 8 - $s), (($globeR + $s) * 2), (($globeR + $s) * 2))
    $sBrush.Dispose()
}

# Globe disc
$globeRect = New-Object System.Drawing.Rectangle ($center - $globeR), ($centerY - $globeR), ($globeR * 2), ($globeR * 2)
$globeBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush ($globeRect, [System.Drawing.Color]::FromArgb(255, 245, 247, 250), [System.Drawing.Color]::FromArgb(255, 205, 212, 222), [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
$g.FillEllipse($globeBrush, $globeRect)
$globeBrush.Dispose()

# Globe border ring
$borderPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 160, 172, 188), [int]($Size * 0.012))
$g.DrawEllipse($borderPen, $globeRect)
$borderPen.Dispose()

# Latitude and Longitude lines on globe (subtle grey lines)
$gridPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(65, 120, 135, 155), [int]($Size * 0.006))
# Equator
$g.DrawLine($gridPen, ($center - $globeR), $centerY, ($center + $globeR), $centerY)
# Latitude curves
$g.DrawArc($gridPen, ($center - $globeR), [int]($centerY - $globeR * 0.55), ($globeR * 2), [int]($globeR * 1.1), 0, 360)
# Longitude meridian ellipses
$g.DrawEllipse($gridPen, [int]($center - $globeR * 0.55), ($centerY - $globeR), [int]($globeR * 1.1), ($globeR * 2))
$g.DrawLine($gridPen, $center, ($centerY - $globeR), $center, ($centerY + $globeR))
$gridPen.Dispose()

# 4. Big Serif 'W' Emblem
# Subtle drop shadow for W
$wFont = New-Object System.Drawing.Font ("Georgia", [float]($Size * 0.30), [System.Drawing.FontStyle]::Bold)
$wFormat = New-Object System.Drawing.StringFormat
$wFormat.Alignment = [System.Drawing.StringAlignment]::Center
$wFormat.LineAlignment = [System.Drawing.StringAlignment]::Center

$wShadowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(80, 20, 30, 45))
$wRectShadow = New-Object System.Drawing.RectangleF $center, ($centerY + [int]($Size * 0.01)), 0, 0
$g.DrawString("W", $wFont, $wShadowBrush, $wRectShadow.X, $wRectShadow.Y, $wFormat)
$wShadowBrush.Dispose()

# W main glyph: deep royal ink
$wBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 24, 38, 56))
$g.DrawString("W", $wFont, $wBrush, $center, $centerY, $wFormat)
$wBrush.Dispose()
$wFont.Dispose()

# 5. The Signature iOS 6 Gloss Curve (exact same as muzika, tikie, tubie, chirpie)
$glossPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$glossHeight = [int]($Size * 0.44)
$glossDip = [int]($Size * 0.53)

$glossPath.AddLine(0, 0, $Size, 0)
$glossPath.AddLine($Size, 0, $Size, $glossHeight)
$glossPath.AddBezier($Size, $glossHeight, [int]($Size * 0.77), $glossDip, [int]($Size * 0.23), $glossDip, 0, $glossHeight)
$glossPath.CloseFigure()

$glossRect = New-Object System.Drawing.Rectangle 0, 0, $Size, $glossDip
$glossBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush ($glossRect, [System.Drawing.Color]::FromArgb(105, 255, 255, 255), [System.Drawing.Color]::FromArgb(15, 255, 255, 255), [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
$g.FillPath($glossBrush, $glossPath)
$glossBrush.Dispose()
$glossPath.Dispose()

$g.Dispose()
$iconPath.Dispose()

$bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host "Generated Wikie icon at: $OutFile"
