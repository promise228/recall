$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$assetDir = Join-Path $root "assets"
$thumbRoot = Join-Path $assetDir "thumbs"
$outputPath = Join-Path $assetDir "gallery-data.js"
$targetOriginalBytes = 1MB

$imageExtensions = @(".jpg", ".jpeg", ".png", ".webp", ".gif")
$thumbableExtensions = @(".jpg", ".jpeg", ".png")
$videoExtensions = @(".mp4", ".mov", ".webm")
$supportedExtensions = $imageExtensions + $videoExtensions

Add-Type -AssemblyName System.Drawing

function Get-AlbumDateParts {
  param(
    [string]$FolderName
  )

  if ($FolderName -match "^(?<location>.+)_(?<date>\d{8})$") {
    $rawDate = $Matches.date
    return @{
      Location = $Matches.location
      DateKey = $rawDate
      Year = [int]$rawDate.Substring(0, 4)
      Month = [int]$rawDate.Substring(4, 2)
      Day = [int]$rawDate.Substring(6, 2)
    }
  }

  return @{
    Location = $FolderName
    DateKey = "00000000"
    Year = 0
    Month = 0
    Day = 0
  }
}

function Get-JpegCodec {
  return [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
    Where-Object { $_.MimeType -eq "image/jpeg" } |
    Select-Object -First 1
}

function Save-JpegVariant {
  param(
    [System.Drawing.Image]$SourceImage,
    [string]$DestinationPath,
    [double]$Scale,
    [int]$Quality
  )

  $targetWidth = [Math]::Max(1, [int][Math]::Round($SourceImage.Width * $Scale))
  $targetHeight = [Math]::Max(1, [int][Math]::Round($SourceImage.Height * $Scale))

  $bitmap = $null
  $graphics = $null

  try {
    $bitmap = New-Object System.Drawing.Bitmap($targetWidth, $targetHeight)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.DrawImage($SourceImage, 0, 0, $targetWidth, $targetHeight)

    $qualityEncoder = [System.Drawing.Imaging.Encoder]::Quality
    $encoderParameters = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $encoderParameters.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter($qualityEncoder, [long]$Quality)
    $bitmap.Save($DestinationPath, (Get-JpegCodec), $encoderParameters)
  }
  finally {
    if ($graphics) {
      $graphics.Dispose()
    }
    if ($bitmap) {
      $bitmap.Dispose()
    }
  }
}

function Ensure-OriginalUnderSize {
  param(
    [System.IO.FileInfo]$File,
    [long]$MaxBytes = $targetOriginalBytes
  )

  if ($File.Extension.ToLowerInvariant() -notin @(".jpg", ".jpeg")) {
    return $File
  }

  if ($File.Length -le $MaxBytes) {
    return $File
  }

  $sourceImage = $null
  $memoryStream = $null
  $tempPath = "$($File.FullName).tmp.jpg"
  $success = $false

  try {
    $memoryStream = New-Object System.IO.MemoryStream(, [System.IO.File]::ReadAllBytes($File.FullName))
    $sourceImage = [System.Drawing.Image]::FromStream($memoryStream)

    $scales = @(1.0, 0.9, 0.82, 0.74, 0.66, 0.58, 0.5, 0.42, 0.34, 0.28, 0.22)
    $qualities = @(86, 78, 70, 62, 54, 46, 38)

    foreach ($scale in $scales) {
      foreach ($quality in $qualities) {
        Save-JpegVariant -SourceImage $sourceImage -DestinationPath $tempPath -Scale $scale -Quality $quality
        $tempItem = Get-Item -LiteralPath $tempPath

        if ($tempItem.Length -le $MaxBytes) {
          $success = $true
          break
        }
      }

      if ($success) {
        break
      }
    }
  }
  finally {
    if ($sourceImage) {
      $sourceImage.Dispose()
    }
    if ($memoryStream) {
      $memoryStream.Dispose()
    }
  }

  if ($success) {
    $tempBytes = [System.IO.File]::ReadAllBytes($tempPath)

    for ($retry = 0; $retry -lt 8; $retry++) {
      try {
        [System.IO.File]::WriteAllBytes($File.FullName, $tempBytes)
        Remove-Item -LiteralPath $tempPath -Force
        return Get-Item -LiteralPath $File.FullName
      }
      catch {
        if ($retry -eq 7) {
          break
        }

        Start-Sleep -Milliseconds 250
      }
    }
  }

  if (Test-Path -LiteralPath $tempPath) {
    Remove-Item -LiteralPath $tempPath -Force
  }

  return $File
}

function Get-ThumbnailRelativePath {
  param(
    [string]$FolderName,
    [string]$FileName
  )

  $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
  return "./assets/thumbs/$FolderName/$baseName.jpg".Replace("\", "/")
}

function Ensure-Thumbnail {
  param(
    [System.IO.FileInfo]$File,
    [string]$FolderName,
    [int]$MaxWidth = 720,
    [int]$Quality = 82
  )

  $extension = $File.Extension.ToLowerInvariant()
  if ($thumbableExtensions -notcontains $extension) {
    return $null
  }

  $albumThumbDir = Join-Path $thumbRoot $FolderName
  if (-not (Test-Path -LiteralPath $albumThumbDir)) {
    New-Item -ItemType Directory -Path $albumThumbDir -Force | Out-Null
  }

  $thumbRelativePath = Get-ThumbnailRelativePath -FolderName $FolderName -FileName $File.Name
  $thumbPath = Join-Path $root ($thumbRelativePath.TrimStart("./").Replace("/", "\"))

  if (Test-Path -LiteralPath $thumbPath) {
    $thumbItem = Get-Item -LiteralPath $thumbPath
    if ($thumbItem.LastWriteTimeUtc -ge $File.LastWriteTimeUtc) {
      return $thumbRelativePath
    }
  }

  $sourceImage = $null
  $bitmap = $null
  $graphics = $null

  try {
    $sourceImage = [System.Drawing.Image]::FromFile($File.FullName)
    $targetWidth = [Math]::Min($sourceImage.Width, $MaxWidth)
    if ($targetWidth -lt 1) {
      $targetWidth = $sourceImage.Width
    }

    $targetHeight = [Math]::Max(1, [int][Math]::Round($sourceImage.Height * ($targetWidth / $sourceImage.Width)))

    $bitmap = New-Object System.Drawing.Bitmap($targetWidth, $targetHeight)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.DrawImage($sourceImage, 0, 0, $targetWidth, $targetHeight)

    $qualityEncoder = [System.Drawing.Imaging.Encoder]::Quality
    $encoderParameters = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $encoderParameters.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter($qualityEncoder, [long]$Quality)
    $bitmap.Save($thumbPath, (Get-JpegCodec), $encoderParameters)
  }
  finally {
    if ($graphics) {
      $graphics.Dispose()
    }
    if ($bitmap) {
      $bitmap.Dispose()
    }
    if ($sourceImage) {
      $sourceImage.Dispose()
    }
  }

  return $thumbRelativePath
}

$albums = @(
  Get-ChildItem -LiteralPath $root -Directory |
    Where-Object { $_.Name -notin @("assets", ".git", ".github") } |
    ForEach-Object {
      $folder = $_
      $dateParts = Get-AlbumDateParts -FolderName $folder.Name
      $media = @(
        Get-ChildItem -LiteralPath $folder.FullName -File |
          Where-Object { $supportedExtensions -contains $_.Extension.ToLowerInvariant() } |
          Sort-Object Name |
          ForEach-Object {
            $file = $_
            if ($thumbableExtensions -contains $file.Extension.ToLowerInvariant()) {
              $file = Ensure-OriginalUnderSize -File $file
            }

            $extension = $file.Extension.ToLowerInvariant()
            $mediaType = if ($videoExtensions -contains $extension) { "video" } else { "image" }
            $sourcePath = "./$($folder.Name)/$($file.Name)".Replace("\", "/")
            $item = @{
              type = $mediaType
              src = $sourcePath
              name = $file.Name
            }

            if ($mediaType -eq "image") {
              $thumbPath = Ensure-Thumbnail -File $file -FolderName $folder.Name
              if ($thumbPath) {
                $item.thumb = $thumbPath
              }
            }

            $item
          }
      )

      if (-not $media -or $media.Count -eq 0) {
        return
      }

      $cover = $media | Where-Object { $_.type -eq "image" } | Select-Object -First 1
      if (-not $cover) {
        $cover = $media[0]
      }

      $photoCount = @($media | Where-Object { $_.type -eq "image" }).Count
      $videoCount = @($media | Where-Object { $_.type -eq "video" }).Count

      @{
        id = $folder.Name
        folder = $folder.Name
        location = $dateParts.Location
        dateKey = $dateParts.DateKey
        year = $dateParts.Year
        month = $dateParts.Month
        day = $dateParts.Day
        displayDate = $dateParts.DateKey
        mediaCount = $media.Count
        photoCount = $photoCount
        videoCount = $videoCount
        cover = $cover
        media = $media
      }
    } |
    Sort-Object @{ Expression = { $_.dateKey }; Descending = $true }, @{ Expression = { $_.location }; Descending = $false }
)

$json = $albums | ConvertTo-Json -Depth 8
$content = @"
window.GALLERY_DATA = $json;
"@

Set-Content -LiteralPath $outputPath -Value $content -Encoding UTF8

[PSCustomObject]@{
  Output = $outputPath
  ThumbnailRoot = $thumbRoot
  TargetOriginalBytes = $targetOriginalBytes
  AlbumCount = ($albums | Measure-Object).Count
  MediaCount = ($albums | ForEach-Object { $_.mediaCount } | Measure-Object -Sum).Sum
}
