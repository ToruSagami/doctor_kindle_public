#requires -Version 7.0
# Copyright 2026 Toru Sagami
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
  KDPの表紙テンプレートZIPと電子書籍用表紙画像から、
  ペーパーバック用の表紙PNGとPDFを生成します。
.VERSION
  0.2.3
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('help', 'test', 'create')]
    [string]$Command = 'help',

    [Parameter()]
    [string]$ProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptVersion = '0.2.3'
$CommandName = 'pdfcover'
$ScriptDir = [System.IO.Path]::GetFullPath($PSScriptRoot)
$RepositoryRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $ScriptDir))
$TemplateDir = Join-Path $RepositoryRoot '70_template'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = $RepositoryRoot
}
elseif ([System.IO.Path]::IsPathRooted($ProjectRoot)) {
    $ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
}
else {
    $ProjectRoot = [System.IO.Path]::GetFullPath(
        (Join-Path (Get-Location).Path $ProjectRoot)
    )
}
$CoverDir = Join-Path $ProjectRoot '30_cover'
$PublishDir = Join-Path $ProjectRoot '90_publish'
$WorkDir = Join-Path $ProjectRoot '98_work'
$ArchiveDir = Join-Path $ProjectRoot '99_archive'
$DefaultDpi = 300.0
$MinimumDpi = 300.0
$RecommendedMaximumDpi = 600.0
$TargetOutputDpi = 300.0
$BleedInches = 0.125
$script:TranscriptStarted = $false
$script:RunningLog = $null
$script:FinalLog = $null
$script:StartTime = Get-Date

function Show-Help {
    $scriptName = Split-Path -Leaf $PSCommandPath
@"
$CommandName $ScriptVersion

電子書籍用の表紙画像とKDPの表紙テンプレートZIPから、
ペーパーバック用の表紙PNGとPDFを生成します。

Usage:
  .\$scriptName
  .\$scriptName help
  .\$scriptName test [-ProjectRoot <path>]
  .\$scriptName create [-ProjectRoot <path>]

Commands:
  help   このヘルプを表示
  test   入力、テンプレート、寸法、DPI、PDF出力環境を確認
  create  確認後、ペーパーバック用のPNGとPDFを生成

Input:
  30_cover\cover.png
  30_cover\cover.jpg
  30_cover\cover.jpeg
  KDP表紙計算ツールからダウンロードしたZIP

ZIP search order:
  1. Windowsのダウンロードフォルダ
  2. プロジェクト直下
  3. 99_archive

Output:
  90_publish\paperback_cover.png
  90_publish\paperback_cover.pdf
  98_work\pdfcover_check_YYYYMMDD_HHMMSS.png

Logs:
  98_work\pdfcover_test_*.log
  98_work\pdfcover_create_*.log

Requirements:
  PowerShell 7以上
  ImageMagickのmagickコマンド
"@
}

function Assert-SafeProjectRoot {
    $fullProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
    $fileSystemRoot = [System.IO.Path]::GetPathRoot($fullProjectRoot)

    if ([string]::Equals(
            $fullProjectRoot.TrimEnd([char[]]@('\', '/')),
            $fileSystemRoot.TrimEnd([char[]]@('\', '/')),
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw "ファイルシステムのルートはProjectRootに指定できません: $fullProjectRoot"
    }

    $templatePrefix = $TemplateDir.TrimEnd([char[]]@('\', '/')) +
        [System.IO.Path]::DirectorySeparatorChar

    if ([string]::Equals(
            $fullProjectRoot,
            $TemplateDir,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -or
        $fullProjectRoot.StartsWith(
            $templatePrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw "70_template自身またはその配下はProjectRootに指定できません: $fullProjectRoot"
    }
}

function Initialize-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO', 'OK', 'WARN', 'ERROR')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "$timestamp [$Level] $Message"
}

function Start-RunLog {
    param([Parameter(Mandatory)][string]$Mode)
    Initialize-Directory -Path $WorkDir
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:RunningLog = Join-Path $WorkDir "${CommandName}_${Mode}_running_${stamp}.log"
    Start-Transcript -Path $script:RunningLog -Force | Out-Null
    $script:TranscriptStarted = $true
    Write-Log INFO "$CommandName version $ScriptVersion"
    Write-Log INFO "Mode: $Mode"
    Write-Log INFO "PowerShell: $($PSVersionTable.PSVersion)"
    Write-Log INFO "Project root: $ProjectRoot"
}

function Stop-RunLog {
    param([Parameter(Mandatory)][ValidateSet('success', 'fail')][string]$Status)
    if ($script:TranscriptStarted) {
        Stop-Transcript | Out-Null
        $script:TranscriptStarted = $false
    }
    if ($script:RunningLog -and (Test-Path -LiteralPath $script:RunningLog)) {
        $name = Split-Path -Leaf $script:RunningLog
        $newName = $name -replace '_running_', "_${Status}_"
        $script:FinalLog = Join-Path $WorkDir $newName
        Move-Item -LiteralPath $script:RunningLog -Destination $script:FinalLog -Force
    }
}

function Invoke-Magick {
    param([Parameter(Mandatory)][string[]]$Arguments)
    & magick @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "ImageMagick failed. Exit code: $LASTEXITCODE`nArguments: $($Arguments -join ' ')"
    }
}

function Get-ImageSize {
    param([Parameter(Mandatory)][string]$Path)
    $raw = & magick identify -format '%w %h' $Path
    if ($LASTEXITCODE -ne 0 -or -not $raw) {
        throw "画像サイズを取得できませんでした: $Path"
    }
    $parts = "$raw".Trim() -split '\s+'
    if ($parts.Count -lt 2) {
        throw "画像サイズの解析に失敗しました: $raw"
    }
    [pscustomobject]@{
        Width = [int]$parts[0]
        Height = [int]$parts[1]
        Area = [int64]$parts[0] * [int64]$parts[1]
    }
}

function Get-ImageDpi {
    param([Parameter(Mandatory)][string]$Path)
    $raw = & magick identify -units PixelsPerInch -format '%x' $Path
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }
    $value = "$raw".Trim() -replace '[^0-9.,-]', ''
    $value = $value -replace ',', '.'
    $dpi = 0.0
    if ([double]::TryParse($value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$dpi)) {
        return $dpi
    }
    return $null
}

function Find-CoverImage {
    $candidates = @(
        (Join-Path $CoverDir 'cover.png'),
        (Join-Path $CoverDir 'cover.jpg'),
        (Join-Path $CoverDir 'cover.jpeg')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw '表紙画像が見つかりません。30_coverにcover.png、cover.jpg、cover.jpegのいずれかを置いてください。'
}

function Get-DownloadsDirectory {
    $userProfile = [Environment]::GetFolderPath('UserProfile')
    $downloads = Join-Path $userProfile 'Downloads'
    if (Test-Path -LiteralPath $downloads) { return $downloads }
    return $null
}

function Get-ZipCandidates {
    $searchDirs = [System.Collections.Generic.List[string]]::new()
    $downloads = Get-DownloadsDirectory
    if ($downloads) { $searchDirs.Add($downloads) }
    $searchDirs.Add($ProjectRoot)
    if (Test-Path -LiteralPath $ArchiveDir) { $searchDirs.Add($ArchiveDir) }

    $results = foreach ($dir in $searchDirs) {
        Get-ChildItem -LiteralPath $dir -File -Filter '*.zip' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)(paperback|cover|template|kdp)' }
    }
    if (-not $results) {
        $results = foreach ($dir in $searchDirs) {
            Get-ChildItem -LiteralPath $dir -File -Filter '*.zip' -ErrorAction SilentlyContinue
        }
    }
    return @($results | Sort-Object LastWriteTime -Descending)
}

function Expand-TemplateZip {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$Zip,
        [Parameter(Mandatory)][string]$Destination
    )
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    Initialize-Directory -Path $Destination
    Expand-Archive -LiteralPath $Zip.FullName -DestinationPath $Destination -Force
}

function Select-TemplatePng {
    param([Parameter(Mandatory)][string]$ExtractDir)
    $pngs = @(Get-ChildItem -LiteralPath $ExtractDir -Recurse -File -Filter '*.png')
    if ($pngs.Count -eq 0) { throw 'ZIP内にPNGファイルが見つかりませんでした。' }
    Write-Log INFO "PNG candidates found in ZIP: $($pngs.Count)"

    $templateNamed = @($pngs | Where-Object { $_.Name -match '(?i)template' })
    if ($templateNamed.Count -eq 1) { return $templateNamed[0] }
    if ($templateNamed.Count -gt 1) {
        $pngs = $templateNamed
        Write-Log INFO "PNG candidates narrowed by filename containing template: $($pngs.Count)"
    }

    $measured = foreach ($png in $pngs) {
        $size = Get-ImageSize -Path $png.FullName
        [pscustomobject]@{
            File = $png
            Width = $size.Width
            Height = $size.Height
            Area = $size.Area
        }
    }

    $largestArea = ($measured | Measure-Object Area -Maximum).Maximum
    $largest = @($measured | Where-Object { $_.Area -eq $largestArea })
    if ($largest.Count -eq 1) { return $largest[0].File }
    $names = ($largest.File.FullName -join "`n")
    throw "テンプレートPNGを一意に選択できませんでした。候補:`n$names"
}

function Initialize-LandscapeTemplate {
    param(
        [Parameter(Mandatory)][string]$InputPath,
        [Parameter(Mandatory)][string]$OutputPath
    )
    $size = Get-ImageSize -Path $InputPath
    Write-Log INFO "Template size before rotation: $($size.Width) x $($size.Height) px"
    if ($size.Width -ge $size.Height) {
        Copy-Item -LiteralPath $InputPath -Destination $OutputPath -Force
        Write-Log INFO 'Rotation applied: No'
        return [pscustomobject]@{ Path = $OutputPath; Width = $size.Width; Height = $size.Height; Rotated = $false }
    }
    Invoke-Magick -Arguments @($InputPath, '-rotate', '90', $OutputPath)
    $rotatedSize = Get-ImageSize -Path $OutputPath
    Write-Log WARN 'Template orientation was rotated automatically.'
    Write-Log INFO 'Rotation applied: 90 degrees clockwise'
    Write-Log INFO "Template size after rotation: $($rotatedSize.Width) x $($rotatedSize.Height) px"
    return [pscustomobject]@{ Path = $OutputPath; Width = $rotatedSize.Width; Height = $rotatedSize.Height; Rotated = $true }
}

function Resolve-TemplateDpi {
    param([Parameter(Mandatory)][string]$TemplatePath)
    $detected = Get-ImageDpi -Path $TemplatePath
    if ($null -eq $detected -or $detected -le 0) {
        Write-Log WARN ('Template DPI metadata was not detected. {0:N0} DPI will be used.' -f $DefaultDpi)
        return $DefaultDpi
    }

    Write-Log INFO ('Detected DPI: {0:N2}' -f $detected)

    if ($detected -lt $MinimumDpi) {
        throw ('Template DPI is below the required minimum of {0:N0} DPI.' -f $MinimumDpi)
    }

    if ($detected -gt $RecommendedMaximumDpi) {
        Write-Log WARN ('Template DPI exceeds the recommended maximum of {0:N0} DPI.' -f $RecommendedMaximumDpi)
    }

    Write-Log OK 'DPI check passed.'
    return $detected
}

function Convert-TemplateToOutputDpi {
    param(
        [Parameter(Mandatory)][string]$InputPath,
        [Parameter(Mandatory)][double]$InputDpi,
        [Parameter(Mandatory)][double]$OutputDpi,
        [Parameter(Mandatory)][string]$OutputPath
    )

    $inputSize = Get-ImageSize -Path $InputPath
    $scale = $OutputDpi / $InputDpi
    $outputWidth = [int][math]::Round($inputSize.Width * $scale)
    $outputHeight = [int][math]::Round($inputSize.Height * $scale)
    $densityText = $OutputDpi.ToString(
        '0.###',
        [System.Globalization.CultureInfo]::InvariantCulture
    )

    if ($outputWidth -le 0 -or $outputHeight -le 0) {
        throw '出力用テンプレートの画素寸法を計算できませんでした。'
    }

    Write-Log INFO (
        'Preparing template for output: {0} x {1} px at {2:N2} DPI' -f
        $outputWidth,
        $outputHeight,
        $OutputDpi
    )

    Invoke-Magick -Arguments @(
        $InputPath,
        '-resize', "${outputWidth}x${outputHeight}!",
        '-units', 'PixelsPerInch',
        '-density', $densityText,
        $OutputPath
    )

    Write-Log OK 'Output template prepared.'
    return [pscustomobject]@{
        Path = $OutputPath
        Width = $outputWidth
        Height = $outputHeight
        Dpi = $OutputDpi
    }
}

function Get-TrimSizeFromName {
    param([Parameter(Mandatory)][string]$Name)

    $foundMatches = [regex]::Matches(
        $Name,
        '(?<!\d)(\d+(?:\.\d+)?)\s*[xX×]\s*(\d+(?:\.\d+)?)(?!\d)'
    )

    foreach ($match in $foundMatches) {
        $width = [double]::Parse(
            $match.Groups[1].Value,
            [System.Globalization.CultureInfo]::InvariantCulture
        )
        $height = [double]::Parse(
            $match.Groups[2].Value,
            [System.Globalization.CultureInfo]::InvariantCulture
        )

        if ($width -gt 1 -and $height -gt 1) {
            return [pscustomobject]@{
                WidthInches = $width
                HeightInches = $height
            }
        }
    }

    return $null
}

function Get-PageCountFromName {
    param([Parameter(Mandatory)][string]$Name)

    $match = [regex]::Match(
        $Name,
        '(?i)_(\d+)_(?:BW|COLOR|STANDARD|PREMIUM)(?:_|\.)'
    )

    if (-not $match.Success) {
        return $null
    }

    return [int]$match.Groups[1].Value
}

function Resolve-FrontCoverWidth {
    param(
        [Parameter(Mandatory)][string]$ZipName,
        [Parameter(Mandatory)][string]$CoverPath,
        [Parameter(Mandatory)][int]$CanvasWidth,
        [Parameter(Mandatory)][int]$CanvasHeight,
        [Parameter(Mandatory)][double]$OutputDpi
    )

    $trimSize = Get-TrimSizeFromName -Name $ZipName

    if ($trimSize) {
        $frontWidth = [int][math]::Round(
            ($trimSize.WidthInches + $BleedInches) * $OutputDpi
        )
        $expectedHeight = (
            $trimSize.HeightInches + (2.0 * $BleedInches)
        ) * $OutputDpi
        $heightDifference = [math]::Abs($CanvasHeight - $expectedHeight)
        $heightDifferencePercent = $heightDifference / $CanvasHeight * 100.0

        Write-Log INFO (
            'Trim size from ZIP filename: {0:N3} x {1:N3} inches' -f
            $trimSize.WidthInches,
            $trimSize.HeightInches
        )
        Write-Log INFO (
            'Template height difference from trim and bleed calculation: {0:N2}%' -f
            $heightDifferencePercent
        )

        if ($heightDifferencePercent -gt 1.0) {
            Write-Log WARN 'Template height differs from the ZIP filename calculation by more than 1.0%.'
        }

        if ($frontWidth -gt 0 -and $frontWidth -lt $CanvasWidth) {
            Write-Log INFO 'Front-cover width source: ZIP filename trim size and bleed'
            return $frontWidth
        }

        throw 'ZIPファイル名から算出した前表紙幅がテンプレート全幅の範囲外です。'
    }

    $coverSize = Get-ImageSize -Path $CoverPath
    $fallbackWidth = [int][math]::Round(
        $CanvasHeight * ($coverSize.Width / [double]$coverSize.Height)
    )
    Write-Log WARN 'ZIPファイル名から判型を取得できないため、表紙画像の縦横比から前表紙幅を推定します。'
    Write-Log INFO 'Front-cover width source: cover image aspect ratio'
    return $fallbackWidth
}

function Get-RepresentativeColor {
    param(
        [Parameter(Mandatory)][string]$CoverPath,
        [Parameter(Mandatory)][string]$WorkPath
    )
    Invoke-Magick -Arguments @(
        $CoverPath,
        '-gravity', 'West',
        '-crop', '5%x100%+0+0',
        '+repage',
        '-statistic', 'Median', '5x5',
        '-resize', '1x1!',
        $WorkPath
    )
    $color = & magick $WorkPath -format '%[pixel:p{0,0}]' info:
    if ($LASTEXITCODE -ne 0 -or -not $color) { throw '代表色を取得できませんでした。' }
    return "$color".Trim()
}

function Test-PdfWrite {
    param([Parameter(Mandatory)][string]$Stamp)
    $testPng = Join-Path $WorkDir "pdfcover_pdf_test_${Stamp}.png"
    $testPdf = Join-Path $WorkDir "pdfcover_pdf_test_${Stamp}.pdf"
    try {
        Invoke-Magick -Arguments @('-size', '16x16', 'xc:white', $testPng)
        Invoke-Magick -Arguments @($testPng, '-units', 'PixelsPerInch', '-density', '300', $testPdf)
        if (-not (Test-Path -LiteralPath $testPdf)) { throw 'PDF test file was not created.' }
        Write-Log OK 'ImageMagick PDF write test passed.'
    } finally {
        Remove-Item -LiteralPath $testPng -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $testPdf -Force -ErrorAction SilentlyContinue
    }
}

function Backup-ExistingFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Stamp
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $dir = Split-Path -Parent $Path
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext = [System.IO.Path]::GetExtension($Path)
    $backup = Join-Path $dir "${base}_${Stamp}${ext}"
    Move-Item -LiteralPath $Path -Destination $backup -Force
    Write-Log INFO "Existing output moved to: $backup"
}

function New-CoverComposite {
    param(
        [Parameter(Mandatory)][string]$CoverPath,
        [Parameter(Mandatory)][string]$TemplatePath,
        [Parameter(Mandatory)][int]$CanvasWidth,
        [Parameter(Mandatory)][int]$CanvasHeight,
        [Parameter(Mandatory)][int]$FrontWidth,
        [Parameter(Mandatory)][double]$OutputDpi,
        [Parameter(Mandatory)][string]$BackgroundColor,
        [Parameter(Mandatory)][string]$CompositePath,
        [Parameter(Mandatory)][string]$CheckPath
    )
    if ($FrontWidth -le 0 -or $FrontWidth -ge $CanvasWidth) {
        throw '表紙領域の推定幅がテンプレート全幅以上になりました。入力画像またはテンプレートを確認してください。'
    }
    $frontX = $CanvasWidth - $FrontWidth
    $coverSize = Get-ImageSize -Path $CoverPath
    $coverScale = [math]::Max(
        $FrontWidth / [double]$coverSize.Width,
        $CanvasHeight / [double]$coverSize.Height
    )
    $densityText = $OutputDpi.ToString(
        '0.###',
        [System.Globalization.CultureInfo]::InvariantCulture
    )
    Write-Log INFO "Cover source size: $($coverSize.Width) x $($coverSize.Height) px"
    Write-Log INFO ('Cover scale factor: {0:N3}' -f $coverScale)
    if ($coverScale -gt 1.0) {
        Write-Log WARN 'The cover image will be enlarged. A higher-resolution source image is recommended.'
    }
    Write-Log INFO 'Cover fit mode: fill'
    Write-Log INFO 'Crop alignment: center'
    Write-Log INFO "Estimated front-cover region: ${FrontWidth} x ${CanvasHeight} px"
    Write-Log INFO "Front-cover X position: $frontX"

    $preparedCover = Join-Path $WorkDir 'pdfcover_front_prepared.png'
    Write-Log INFO 'Composite step 1 of 4: preparing the front cover.'
    Invoke-Magick -Arguments @(
        $CoverPath,
        '-resize', "${FrontWidth}x${CanvasHeight}^",
        '-gravity', 'Center',
        '-extent', "${FrontWidth}x${CanvasHeight}",
        $preparedCover
    )
    Write-Log INFO 'Composite step 2 of 4: building the full cover canvas.'
    Invoke-Magick -Arguments @(
        '-size', "${CanvasWidth}x${CanvasHeight}",
        "xc:$BackgroundColor",
        $preparedCover,
        '-geometry', "+${frontX}+0",
        '-composite',
        '-units', 'PixelsPerInch',
        '-density', $densityText,
        $CompositePath
    )

    $templateOverlay = Join-Path $WorkDir 'pdfcover_template_overlay.png'
    Write-Log INFO 'Composite step 3 of 4: preparing the template overlay.'
    Invoke-Magick -Arguments @(
        $TemplatePath,
        '-alpha', 'set',
        '-channel', 'A',
        '-evaluate', 'multiply', '0.35',
        '+channel',
        $templateOverlay
    )
    Write-Log INFO 'Composite step 4 of 4: creating the check image.'
    Invoke-Magick -Arguments @($CompositePath, $templateOverlay, '-composite', $CheckPath)
    Remove-Item -LiteralPath $preparedCover -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $templateOverlay -Force -ErrorAction SilentlyContinue
}

if ($Command -eq 'help') {
    Show-Help
    exit 0
}

Assert-SafeProjectRoot
Initialize-Directory -Path $PublishDir
Initialize-Directory -Path $WorkDir
Initialize-Directory -Path $ArchiveDir
$mode = $Command
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$extractDir = Join-Path $WorkDir "pdfcover_extract_${stamp}"
$normalizedTemplate = Join-Path $WorkDir "pdfcover_template_${stamp}.png"
$outputTemplate = Join-Path $WorkDir "pdfcover_template_output_${stamp}.png"
$representativeColorImage = Join-Path $WorkDir "pdfcover_color_${stamp}.png"
$compositeWork = Join-Path $WorkDir "pdfcover_composite_${stamp}.png"
$checkImage = Join-Path $WorkDir "pdfcover_check_${stamp}.png"

try {
    Start-RunLog -Mode $mode
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw "PowerShell 7以上が必要です。現在のバージョン: $($PSVersionTable.PSVersion)"
    }
    if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
        throw 'ImageMagickのmagickコマンドが見つかりません。'
    }
    Write-Log OK 'ImageMagick command found.'
    Test-PdfWrite -Stamp $stamp

    $cover = Find-CoverImage
    Write-Log INFO "Selected cover image: $cover"

    $zipCandidates = @(Get-ZipCandidates)
    Write-Log INFO "ZIP candidates found: $($zipCandidates.Count)"
    if ($zipCandidates.Count -eq 0) {
        throw 'KDP表紙テンプレートのZIPが見つかりません。ダウンロードフォルダ、プロジェクト直下、99_archiveを確認してください。'
    }

    $selectedZip = $zipCandidates[0]
    Write-Log INFO "Selected ZIP: $($selectedZip.FullName)"
    Write-Log INFO "Selected ZIP modified: $($selectedZip.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    $templatePageCount = Get-PageCountFromName -Name $selectedZip.Name
    if ($null -ne $templatePageCount) {
        Write-Log INFO "Template page count from ZIP filename: $templatePageCount"
        Write-Log WARN 'Confirm that the template page count matches the final interior PDF.'
    }
    Expand-TemplateZip -Zip $selectedZip -Destination $extractDir

    $templatePng = Select-TemplatePng -ExtractDir $extractDir
    Write-Log INFO "Selected template PNG: $($templatePng.FullName)"
    $sourceTemplate = Initialize-LandscapeTemplate -InputPath $templatePng.FullName -OutputPath $normalizedTemplate
    $templateDpi = Resolve-TemplateDpi -TemplatePath $sourceTemplate.Path
    $outputDpi = $TargetOutputDpi
    $template = Convert-TemplateToOutputDpi -InputPath $sourceTemplate.Path -InputDpi $templateDpi -OutputDpi $outputDpi -OutputPath $outputTemplate
    $physicalWidth = $template.Width / $outputDpi
    $physicalHeight = $template.Height / $outputDpi
    Write-Log INFO ('Output DPI: {0:N2}' -f $outputDpi)
    Write-Log INFO ('Output physical size: {0:N3} x {1:N3} inches' -f $physicalWidth, $physicalHeight)
    $frontWidth = Resolve-FrontCoverWidth -ZipName $selectedZip.Name -CoverPath $cover -CanvasWidth $template.Width -CanvasHeight $template.Height -OutputDpi $outputDpi

    $backgroundColor = Get-RepresentativeColor -CoverPath $cover -WorkPath $representativeColorImage
    Write-Log INFO "Background color: $backgroundColor"

    New-CoverComposite -CoverPath $cover -TemplatePath $template.Path -CanvasWidth $template.Width -CanvasHeight $template.Height -FrontWidth $frontWidth -OutputDpi $outputDpi -BackgroundColor $backgroundColor -CompositePath $compositeWork -CheckPath $checkImage
    Write-Log OK "Check image created: $checkImage"

    if ($mode -eq 'test') {
        Write-Log OK 'Test completed. No publication files were created.'
    } elseif ($mode -eq 'create') {
        $outputPng = Join-Path $PublishDir 'paperback_cover.png'
        $outputPdf = Join-Path $PublishDir 'paperback_cover.pdf'
        Backup-ExistingFile -Path $outputPng -Stamp $stamp
        Backup-ExistingFile -Path $outputPdf -Stamp $stamp
        Copy-Item -LiteralPath $compositeWork -Destination $outputPng -Force
        $densityText = $outputDpi.ToString(
            '0.###',
            [System.Globalization.CultureInfo]::InvariantCulture
        )
        Invoke-Magick -Arguments @($outputPng, '-colorspace', 'sRGB', '-units', 'PixelsPerInch', '-density', $densityText, $outputPdf)
        Write-Log OK "Output PNG: $outputPng"
        Write-Log OK "Output PDF: $outputPdf"
    }

    $elapsed = (Get-Date) - $script:StartTime
    Write-Log INFO ('Elapsed time: {0:N1} seconds' -f $elapsed.TotalSeconds)
    Stop-RunLog -Status 'success'
    if ($script:FinalLog) { Write-Host "Log: $script:FinalLog" }
    exit 0
} catch {
    Write-Log ERROR $_.Exception.Message
    if ($_.ScriptStackTrace) { Write-Host $_.ScriptStackTrace }
    Stop-RunLog -Status 'fail'
    if ($script:FinalLog) { Write-Host "Log: $script:FinalLog" }
    exit 1
} finally {
    Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $normalizedTemplate -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $outputTemplate -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $representativeColorImage -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $compositeWork -Force -ErrorAction SilentlyContinue
}
