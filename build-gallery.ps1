$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$assetDir = Join-Path $root "assets"
$outputPath = Join-Path $assetDir "gallery-data.js"

$imageExtensions = @(".jpg", ".jpeg", ".png", ".webp", ".gif")
$videoExtensions = @(".mp4", ".mov", ".webm")
$supportedExtensions = $imageExtensions + $videoExtensions

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

$albums = @(
  Get-ChildItem -LiteralPath $root -Directory |
    Where-Object { $_.Name -ne "assets" } |
    ForEach-Object {
      $folder = $_
      $dateParts = Get-AlbumDateParts -FolderName $folder.Name
      $media = @(
        Get-ChildItem -LiteralPath $folder.FullName -File |
          Where-Object { $supportedExtensions -contains $_.Extension.ToLowerInvariant() } |
          Sort-Object Name |
          ForEach-Object {
            $extension = $_.Extension.ToLowerInvariant()
            $mediaType = if ($videoExtensions -contains $extension) { "video" } else { "image" }
            @{
              type = $mediaType
              src = "./$($folder.Name)/$($_.Name)".Replace("\", "/")
              name = $_.Name
            }
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
  AlbumCount = ($albums | Measure-Object).Count
  MediaCount = ($albums | ForEach-Object { $_.mediaCount } | Measure-Object -Sum).Sum
}
