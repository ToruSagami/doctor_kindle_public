# Copyright 2026 Toru Sagami
# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("setup", "check", "config", "help", "master", "tree", "epub", "pdf", "docx", "all", "clean")]
    [string]$Task = "master",

    [Parameter()]
    [string]$ProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$BookScriptVersion = "0.7.5"

# スクリプトは77_scriptへ置き、その親フォルダを配布元ルートとして扱う。
# ProjectRootを省略した場合は、従来どおり配布元ルートを生成対象にする。
$ScriptDir = [System.IO.Path]::GetFullPath($PSScriptRoot)
$RepositoryRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $ScriptDir))
$TemplateDir = Join-Path $RepositoryRoot "70_template"

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

# 親ディレクトリ名を成果物のベース名として使用する
# 空白とWindowsのファイル名に使えない文字はハイフンへ変換する
$ProjectName = Split-Path $ProjectRoot -Leaf
$OutputBaseName = $ProjectName.Trim()
$OutputBaseName = $OutputBaseName -replace '\s+', '-'
$OutputBaseName = $OutputBaseName -replace '[<>:"/\\|?*]', '-'
$OutputBaseName = $OutputBaseName -replace '-+', '-'
$OutputBaseName = $OutputBaseName.Trim(' ', '.', '-')

if ([string]::IsNullOrWhiteSpace($OutputBaseName)) {
    $OutputBaseName = "book"
}
$ManuscriptDir = Join-Path $ProjectRoot "10_manuscript"
$ConfigDir    = Join-Path $ProjectRoot "50_config"
$StyleDir     = Join-Path $ProjectRoot "60_style"
$FigureDir    = Join-Path $ProjectRoot "21_figure"
$WorkDir      = Join-Path $ProjectRoot "98_work"
$PublishDir   = Join-Path $ProjectRoot "90_publish"

$LogTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogBaseName = "book_{0}" -f $Task
$RunningLogFile = Join-Path $WorkDir (
    "{0}_running_{1}.log" -f $LogBaseName, $LogTimestamp
)
$script:TranscriptStarted = $false


function Start-BookLog {
    if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) {
        New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    }

    Start-Transcript -LiteralPath $RunningLogFile -Force | Out-Null
    $script:TranscriptStarted = $true
}


function Complete-BookLog {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("success", "fail")]
        [string]$Status
    )

    if ($script:TranscriptStarted) {
        Stop-Transcript | Out-Null
        $script:TranscriptStarted = $false
    }

    if (-not (Test-Path -LiteralPath $RunningLogFile -PathType Leaf)) {
        return
    }

    $completedLogFile = Join-Path $WorkDir (
        "{0}_{1}_{2}.log" -f $LogBaseName, $Status, $LogTimestamp
    )

    Move-Item `
        -LiteralPath $RunningLogFile `
        -Destination $completedLogFile `
        -Force
}


# 結合順をここで固定する
# 99_master.mdは出力専用なので、この一覧には含めない
$ChapterFiles = @(
    "00_intro.md",
    "01_problem.md",
    "02_solution.md",
    "03_cases.md",
    "04_first_step.md",
    "05_outro.md",
    "06_appendix.md"
)

$MasterFile = Join-Path $ManuscriptDir "99_master.md"
$MetadataFile = Join-Path $ConfigDir "metadata.yaml"
$ColophonFilterFile = Join-Path $StyleDir "colophon.lua"
$HeadingNumberFilterFile = Join-Path $StyleDir "heading-numbering.lua"
$PageBreakFilterFile = Join-Path $StyleDir "pagebreak.lua"
$TableCaptionFilterFile = Join-Path $StyleDir "table-caption.lua"
$CodePlainFilterFile = Join-Path $StyleDir "code-plain.lua"

# treeで使用する雛形は70_template内の実ファイルを唯一の原本とする。

function Get-LogLineTimestamp {
    return Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}


function Write-Info {
    param([string]$Message)

    Write-Host (
        "{0} [INFO] {1}" -f
        (Get-LogLineTimestamp),
        $Message
    ) -ForegroundColor Cyan
}


function Write-Success {
    param([string]$Message)

    Write-Host (
        "{0} [OK]   {1}" -f
        (Get-LogLineTimestamp),
        $Message
    ) -ForegroundColor Green
}


function Write-WarningMessage {
    param([string]$Message)

    Write-Host (
        "{0} [WARN] {1}" -f
        (Get-LogLineTimestamp),
        $Message
    ) -ForegroundColor Yellow
}


function Write-ExternalCommandOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [AllowEmptyString()]
        [string]$Message
    )

    Write-Host (
        "{0} [{1}] {2}" -f
        (Get-LogLineTimestamp),
        $CommandName.ToUpperInvariant(),
        $Message
    )
}

function Ensure-Directories {
    $directories = @(
        $ManuscriptDir,
        $ConfigDir,
        $FigureDir,
        $WorkDir,
        $PublishDir
    )

    foreach ($directory in $directories) {
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            Write-Info "フォルダを作成しました: $directory"
        }
    }
}


function Assert-SafeProjectRoot {
    if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
        throw "ProjectRootが空です。処理を中止します。"
    }

    $fullProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
    $fileSystemRoot = [System.IO.Path]::GetPathRoot($fullProjectRoot)

    if ([string]::Equals(
            $fullProjectRoot.TrimEnd([char[]]@("\", "/")),
            $fileSystemRoot.TrimEnd([char[]]@("\", "/")),
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw "ファイルシステムのルートはProjectRootに指定できません: $fullProjectRoot"
    }

    $templateRootPrefix = $TemplateDir.TrimEnd([char[]]@("\", "/")) +
        [System.IO.Path]::DirectorySeparatorChar

    if ([string]::Equals(
            $fullProjectRoot,
            $TemplateDir,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -or
        $fullProjectRoot.StartsWith(
            $templateRootPrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw "70_template自身またはその配下はProjectRootに指定できません: $fullProjectRoot"
    }
}


function Initialize-ProjectFromTemplate {
    Assert-SafeProjectRoot

    if (-not (Test-Path -LiteralPath $TemplateDir -PathType Container)) {
        throw "雛形の原本が見つかりません: $TemplateDir"
    }

    if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $ProjectRoot -Force | Out-Null
        Write-Info "プロジェクトルートを作成しました: $ProjectRoot"
    }

    Write-Info "70_templateから不足ファイルをコピーします。"
    Write-Info "雛形: $TemplateDir"
    Write-Info "コピー先: $ProjectRoot"

    $templateRootPrefix = $TemplateDir.TrimEnd([char[]]@("\", "/")) +
        [System.IO.Path]::DirectorySeparatorChar

    $templateItems = @(
        Get-ChildItem -LiteralPath $TemplateDir -Force -Recurse |
            Sort-Object -Property @(
                @{ Expression = { if ($_.PSIsContainer) { 0 } else { 1 } } },
                @{ Expression = { $_.FullName } }
            )
    )

    foreach ($item in $templateItems) {
        $relativePath = $item.FullName.Substring($templateRootPrefix.Length)

        # 70_template自身の説明用READMEは、生成先のルートへコピーしない。
        if ($relativePath -eq "README.md") {
            continue
        }

        $destination = Join-Path $ProjectRoot $relativePath

        if ($item.PSIsContainer) {
            if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
                New-Item -ItemType Directory -Path $destination -Force | Out-Null
                Write-Success "フォルダを作成しました: $destination"
            }
            continue
        }

        $destinationParent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
            New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
        }

        if (Test-Path -LiteralPath $destination) {
            Write-WarningMessage "既存ファイルは変更しません: $destination"
            continue
        }

        Copy-Item -LiteralPath $item.FullName -Destination $destination
        Write-Success "雛形をコピーしました: $destination"
    }

    Write-Success "プロジェクトの初期構成を確認しました。"
}

function Get-ChapterPaths {
    $paths = foreach ($fileName in $ChapterFiles) {
        Join-Path $ManuscriptDir $fileName
    }

    return $paths
}

function Assert-ChapterFiles {
    $missingFiles = @()

    foreach ($path in Get-ChapterPaths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $missingFiles += $path
        }
    }

    if ($missingFiles.Count -gt 0) {
        $message = @(
            "次の原稿ファイルが見つかりません。",
            ($missingFiles | ForEach-Object { "  $_" }),
            "",
            "manuscriptフォルダとファイル名を確認してください。"
        ) -join [Environment]::NewLine

        throw $message
    }
}

function Get-PandocInlineText {
    param($Inline)

    if ($null -eq $Inline) {
        return ""
    }

    $typeProperty = $Inline.PSObject.Properties["t"]
    if ($null -eq $typeProperty) {
        return [string]$Inline
    }

    switch ([string]$Inline.t) {
        "Str"       { return [string]$Inline.c }
        "Space"     { return " " }
        "SoftBreak" { return " " }
        "LineBreak" { return " " }
        "Code"      { return [string]$Inline.c[1] }
        "Math"      { return [string]$Inline.c[1] }
        default      { return "" }
    }
}

function Convert-PandocMetaToText {
    param(
        $Value,
        [string]$ListSeparator = "、"
    )

    if ($null -eq $Value) {
        return ""
    }

    $typeProperty = $Value.PSObject.Properties["t"]
    if ($null -eq $typeProperty) {
        return [string]$Value
    }

    switch ([string]$Value.t) {
        "MetaString" {
            return [string]$Value.c
        }
        "MetaBool" {
            return ([string]$Value.c).ToLowerInvariant()
        }
        "MetaInlines" {
            return (($Value.c | ForEach-Object { Get-PandocInlineText $_ }) -join "").Trim()
        }
        "MetaBlocks" {
            $parts = foreach ($block in $Value.c) {
                if ([string]$block.t -eq "Plain" -or [string]$block.t -eq "Para") {
                    (($block.c | ForEach-Object { Get-PandocInlineText $_ }) -join "").Trim()
                }
            }
            return (($parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join " ").Trim()
        }
        "MetaList" {
            $items = foreach ($item in $Value.c) {
                $text = Convert-PandocMetaToText -Value $item -ListSeparator $ListSeparator
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    $text
                }
            }
            return ($items -join $ListSeparator)
        }
        default {
            return ""
        }
    }
}

function Get-PandocMetaProperty {
    param(
        $Container,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $Container) {
        return $null
    }

    $property = $Container.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-PandocMetaMap {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    $typeProperty = $Value.PSObject.Properties["t"]
    if ($null -eq $typeProperty -or [string]$Value.t -ne "MetaMap") {
        return $null
    }

    return $Value.c
}

function Convert-ToBooleanValue {
    param(
        $Value,
        [bool]$Default = $true
    )

    if ($null -eq $Value) {
        return $Default
    }

    $text = (Convert-PandocMetaToText -Value $Value).Trim().ToLowerInvariant()

    if ($text -in @("false", "no", "0", "off")) {
        return $false
    }

    if ($text -in @("true", "yes", "1", "on")) {
        return $true
    }

    return $Default
}

function Format-ColophonDate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DateText,
        [string]$LanguageTag
    )

    $parsedDate = [datetime]::MinValue
    $parsed = [datetime]::TryParseExact(
        $DateText,
        "yyyy-MM-dd",
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$parsedDate
    )

    if (-not $parsed) {
        return $DateText
    }

    $normalizedLanguage = $LanguageTag.Trim().Replace("_", "-").ToLowerInvariant()

    if ($normalizedLanguage -eq "ja" -or $normalizedLanguage.StartsWith("ja-")) {
        return ("{0}年{1}月{2}日" -f $parsedDate.Year, $parsedDate.Month, $parsedDate.Day)
    }

    if ([string]::IsNullOrWhiteSpace($normalizedLanguage)) {
        return $DateText
    }

    try {
        $culture = [System.Globalization.CultureInfo]::GetCultureInfo($normalizedLanguage)
        return $parsedDate.ToString("D", $culture)
    }
    catch {
        return $DateText
    }
}


function Get-ColophonCopyrightText {
    param(
        [string]$Rights,
        [Parameter(Mandatory = $true)]
        [string]$PublicationDate,
        [string]$CopyrightYear,
        [string]$CopyrightHolder,
        [string]$Author
    )

    $publicationYear = ""
    if ($PublicationDate -match '^(?<year>\d{4})(?:-\d{2}-\d{2})?$') {
        $publicationYear = $Matches['year']
    }

    $year = if ($null -eq $CopyrightYear) { "" } else { $CopyrightYear.Trim() }
    $holder = if ($null -eq $CopyrightHolder) { "" } else { $CopyrightHolder.Trim() }

    if ([string]::IsNullOrWhiteSpace($year) -and $Rights -match '(?<!\d)(?<year>\d{4})(?!\d)') {
        $year = $Matches['year']
    }

    if ([string]::IsNullOrWhiteSpace($year)) {
        $year = $publicationYear
    }

    if ([string]::IsNullOrWhiteSpace($holder) -and -not [string]::IsNullOrWhiteSpace($Rights)) {
        $holder = $Rights.Trim()
        $holder = $holder -replace '(?i)^copyright\s*', ''
        $holder = $holder -replace '^©\s*', ''
        $holder = $holder -replace '(?<!\d)\d{4}(?!\d)', ''
        $holder = $holder.Trim([char[]]@(' ', "`t", ':', '：', '-', '–', '—'))
    }

    if ([string]::IsNullOrWhiteSpace($holder)) {
        $holder = if ($null -eq $Author) { "" } else { $Author.Trim() }
    }

    if ([string]::IsNullOrWhiteSpace($year) -or [string]::IsNullOrWhiteSpace($holder)) {
        if (-not [string]::IsNullOrWhiteSpace($Rights)) {
            return $Rights.Trim()
        }
        return ""
    }

    return ("Copyright © {0} {1}" -f $year, $holder)
}

function Show-MetadataAndColophonPreview {
    if (-not (Test-Path -LiteralPath $MetadataFile -PathType Leaf)) {
        Write-WarningMessage ("メタデータ表示を省略します。metadata.yamlが見つかりません: {0}" -f $MetadataFile)
        return
    }

    $metadataInputFile = Join-Path $WorkDir "check-metadata-input.md"
    $metadataJsonFile = $null
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)

    try {
        [System.IO.File]::WriteAllText(
            $metadataInputFile,
            "",
            $utf8WithoutBom
        )

        # PandocのJSONは標準出力経由で受け取らず、固有名の一時ファイルへ出力する。
        # PowerShellによる標準出力の文字列化でJSONが壊れる問題を避ける。
        # ファイル名を毎回変えることで、Dropboxなどによる前回ファイルのロックとも競合しにくくする。
        $metadataJsonFile = Join-Path $WorkDir ("check-metadata-{0}.json" -f [guid]::NewGuid().ToString("N"))

        & pandoc `
            $metadataInputFile `
            "--from=markdown" `
            "--to=json" `
            "--metadata-file=$MetadataFile" `
            "--output=$metadataJsonFile"

        if ($LASTEXITCODE -ne 0) {
            throw "Pandocによるメタデータ確認に失敗しました。終了コード: $LASTEXITCODE"
        }

        if (-not (Test-Path -LiteralPath $metadataJsonFile -PathType Leaf)) {
            throw "Pandocからメタデータ確認用JSONが生成されませんでした: $metadataJsonFile"
        }

        $jsonText = $null
        $readError = $null

        for ($attempt = 1; $attempt -le 5; $attempt++) {
            try {
                $jsonText = [System.IO.File]::ReadAllText($metadataJsonFile)
                $readError = $null
                break
            }
            catch {
                $readError = $_
                Start-Sleep -Milliseconds (100 * $attempt)
            }
        }

        if ($null -ne $readError) {
            throw ("メタデータ確認用JSONを読み込めませんでした: {0}" -f $metadataJsonFile)
        }

        if ([string]::IsNullOrWhiteSpace($jsonText)) {
            throw "Pandocから取得したメタデータ確認用JSONが空です。"
        }

        try {
            $document = $jsonText | ConvertFrom-Json
        }
        catch {
            throw ("Pandocのメタデータ確認用JSONを解析できませんでした: {0}" -f $_.Exception.Message)
        }
        $meta = $document.meta

        Write-Host ""
        Write-Info "Pandocが認識したメタデータ"

        $metadataProperties = @($meta.PSObject.Properties | Sort-Object Name)
        if ($metadataProperties.Count -eq 0) {
            Write-WarningMessage "Pandocが認識したメタデータはありません。"
        }
        else {
            foreach ($property in $metadataProperties) {
                $name = [string]$property.Name
                $value = $property.Value
                $map = Get-PandocMetaMap -Value $value

                if ($null -ne $map) {
                    Write-Host ("       {0}:" -f $name)

                    $nestedProperties = @($map.PSObject.Properties | Sort-Object Name)
                    if ($nestedProperties.Count -eq 0) {
                        Write-Host "         （空のマップ）"
                    }
                    else {
                        foreach ($nestedProperty in $nestedProperties) {
                            $nestedText = Convert-PandocMetaToText -Value $nestedProperty.Value
                            if ([string]::IsNullOrWhiteSpace($nestedText)) {
                                $nestedText = "（空欄）"
                            }
                            Write-Host ("         {0}: {1}" -f $nestedProperty.Name, $nestedText)
                        }
                    }
                }
                else {
                    $displayText = Convert-PandocMetaToText -Value $value
                    if ([string]::IsNullOrWhiteSpace($displayText)) {
                        $displayText = "（空欄）"
                    }
                    Write-Host ("       {0}: {1}" -f $name, $displayText)
                }
            }
        }

        Write-Host ""
        Write-Info "奥付生成チェック"

        $colophonValue = Get-PandocMetaProperty -Container $meta -Name "colophon"
        $colophon = Get-PandocMetaMap -Value $colophonValue
        $enabledValue = Get-PandocMetaProperty -Container $colophon -Name "enabled"
        $enabled = Convert-ToBooleanValue -Value $enabledValue -Default $true

        Write-Host ("       奥付生成：{0}" -f $(if ($enabled) { "有効" } else { "無効" }))

        if (-not $enabled) {
            Write-WarningMessage "metadata.yamlで奥付が無効化されています。master生成時に奥付は追加されません。"
            return
        }

        $title = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $meta -Name "title")
        $subtitle = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $meta -Name "subtitle")
        $author = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $meta -Name "author")
        $dateText = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $meta -Name "date")
        $languageTag = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $meta -Name "lang")
        $rights = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $meta -Name "rights")

        $missingRequired = @()
        if ([string]::IsNullOrWhiteSpace($title)) { $missingRequired += "title" }
        if ([string]::IsNullOrWhiteSpace($author)) { $missingRequired += "author" }
        if ([string]::IsNullOrWhiteSpace($dateText)) { $missingRequired += "date" }

        if ($missingRequired.Count -gt 0) {
            Write-WarningMessage ("奥付生成に必要なメタデータが不足しています: {0}" -f ($missingRequired -join ", "))
            return
        }

        $localizedDate = Format-ColophonDate -DateText $dateText -LanguageTag $languageTag
        $edition = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $colophon -Name "edition")
        $printing = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $colophon -Name "printing")
        $publisher = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $colophon -Name "publisher")
        $publisherPerson = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $colophon -Name "publisher_person")
        $contact = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $colophon -Name "contact")
        $copyrightYear = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $colophon -Name "copyright_year")
        $copyrightHolder = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $colophon -Name "copyright_holder")

        $copyrightText = Get-ColophonCopyrightText `
            -Rights $rights `
            -PublicationDate $dateText `
            -CopyrightYear $copyrightYear `
            -CopyrightHolder $copyrightHolder `
            -Author $author

        Write-Success "奥付生成に必要な必須メタデータを確認しました。"
        Write-Host ("       元の日付: {0}" -f $dateText)
        Write-Host ("       言語タグ: {0}" -f $(if ([string]::IsNullOrWhiteSpace($languageTag)) { "（未設定）" } else { $languageTag }))
        Write-Host ("       表示日付: {0}" -f $localizedDate)
        Write-Host ("       元のrights: {0}" -f $(if ([string]::IsNullOrWhiteSpace($rights)) { "（未設定）" } else { $rights }))
        Write-Host ("       著作権表示: {0}" -f $(if ([string]::IsNullOrWhiteSpace($copyrightText)) { "（未生成）" } else { $copyrightText }))

        Write-Host ""
        Write-Info "生成予定の奥付"
        Write-Host ("       書名：{0}" -f $title)
        if (-not [string]::IsNullOrWhiteSpace($subtitle)) {
            Write-Host ("       副題：{0}" -f $subtitle)
        }
        Write-Host ("       発行日：{0}" -f $localizedDate)

        if (-not [string]::IsNullOrWhiteSpace($edition)) {
            Write-Host ("       版：{0}" -f $edition)
        }
        if (-not [string]::IsNullOrWhiteSpace($printing)) {
            Write-Host ("       刷：{0}" -f $printing)
        }

        Write-Host ("       著者：{0}" -f $author)

        if (-not [string]::IsNullOrWhiteSpace($publisher)) {
            Write-Host ("       発行所：{0}" -f $publisher)
        }
        if (-not [string]::IsNullOrWhiteSpace($publisherPerson)) {
            Write-Host ("       発行人：{0}" -f $publisherPerson)
        }
        if (-not [string]::IsNullOrWhiteSpace($contact)) {
            Write-Host ("       連絡先：{0}" -f $contact)
        }
        if (-not [string]::IsNullOrWhiteSpace($copyrightText)) {
            Write-Host ("       {0}" -f $copyrightText)
        }

        if (Test-Path -LiteralPath $MasterFile -PathType Leaf) {
            $masterText = [System.IO.File]::ReadAllText($MasterFile)
            $colophonCount = [regex]::Matches($masterText, '(?m)^:::\s*\{\.colophon\}\s*$').Count

            if ($colophonCount -eq 1) {
                Write-Success "現在の99_master.mdに奥付が1件存在します。"
            }
            elseif ($colophonCount -eq 0) {
                Write-WarningMessage "現在の99_master.mdには奥付がありません。master実行時に追加されます。"
            }
            else {
                Write-WarningMessage ("現在の99_master.mdに奥付が複数存在します: {0}件" -f $colophonCount)
            }
        }
        else {
            Write-WarningMessage "99_master.mdはまだありません。master実行時に生成されます。"
        }
    }
    finally {
        $temporaryFiles = @(
            $metadataInputFile
            $metadataJsonFile
        ) | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        }

        foreach ($temporaryFile in $temporaryFiles) {
            if (-not (Test-Path -LiteralPath $temporaryFile -PathType Leaf)) {
                continue
            }

            $removed = $false

            for ($attempt = 1; $attempt -le 5; $attempt++) {
                try {
                    Remove-Item -LiteralPath $temporaryFile -Force
                    $removed = $true
                    break
                }
                catch {
                    Start-Sleep -Milliseconds (100 * $attempt)
                }
            }

            if (-not $removed) {
                Write-WarningMessage ("確認用一時ファイルを削除できませんでした。次回の処理には影響しません: {0}" -f $temporaryFile)
            }
        }
    }
}

function Remove-TemporaryFileSafely {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [int]$MaxAttempts = 5,

        [int]$DelayMilliseconds = 250
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Remove-Item `
                -LiteralPath $Path `
                -Force `
                -ErrorAction Stop

            return
        }
        catch {
            if ($attempt -lt $MaxAttempts) {
                Start-Sleep -Milliseconds $DelayMilliseconds
                continue
            }

            Write-WarningMessage (
                "一時ファイルを削除できませんでした。生成結果には影響しません: {0}" -f
                $Path
            )
        }
    }
}

function Add-ColophonToMaster {
    if (-not (Test-Path -LiteralPath $MasterFile -PathType Leaf)) {
        throw "奥付を追加する99_master.mdが見つかりません: $MasterFile"
    }

    if (-not (Test-Path -LiteralPath $MetadataFile -PathType Leaf)) {
        throw "奥付生成に必要なmetadata.yamlが見つかりません: $MetadataFile"
    }

    Assert-Command `
        -CommandName "pandoc" `
        -InstallHint "winget install --id JohnMacFarlane.Pandoc --exact を実行してください。"

    $metadataJsonFile = Join-Path `
        $WorkDir `
        ("colophon-metadata-{0}.json" -f [guid]::NewGuid().ToString("N"))

    try {
        & pandoc `
            $MasterFile `
            "--from=markdown" `
            "--to=json" `
            "--metadata-file=$MetadataFile" `
            "--output=$metadataJsonFile"

        if ($LASTEXITCODE -ne 0) {
            throw "Pandocによる奥付メタデータの読み込みに失敗しました。終了コード: $LASTEXITCODE"
        }

        if (-not (Test-Path -LiteralPath $metadataJsonFile -PathType Leaf)) {
            throw "PandocのメタデータJSONが生成されませんでした: $metadataJsonFile"
        }

        $jsonText = [System.IO.File]::ReadAllText($metadataJsonFile)
        $document = $jsonText | ConvertFrom-Json
        $meta = $document.meta

        $colophonValue = Get-PandocMetaProperty -Container $meta -Name "colophon"
        $colophon = Get-PandocMetaMap -Value $colophonValue
        $enabledValue = Get-PandocMetaProperty -Container $colophon -Name "enabled"

        if (-not (Convert-ToBooleanValue -Value $enabledValue -Default $true)) {
            Write-WarningMessage "metadata.yamlで奥付が無効化されています。99_master.mdへは追加しません。"
            return
        }

        $title = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $meta -Name "title")
        $subtitle = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $meta -Name "subtitle")
        $author = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $meta -Name "author")
        $dateText = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $meta -Name "date")
        $languageTag = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $meta -Name "lang")
        $rights = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $meta -Name "rights")

        $missingRequired = @()
        if ([string]::IsNullOrWhiteSpace($title)) { $missingRequired += "title" }
        if ([string]::IsNullOrWhiteSpace($author)) { $missingRequired += "author" }
        if ([string]::IsNullOrWhiteSpace($dateText)) { $missingRequired += "date" }

        if ($missingRequired.Count -gt 0) {
            throw ("奥付生成に必要なメタデータが不足しています: {0}" -f ($missingRequired -join ", "))
        }

        $localizedDate = Format-ColophonDate -DateText $dateText -LanguageTag $languageTag
        Write-Info ("発行日を奥付表示用に変換しました: {0} → {1}" -f $dateText, $localizedDate)

        $edition = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $colophon -Name "edition")
        $printing = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $colophon -Name "printing")
        $publisher = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $colophon -Name "publisher")
        $publisherPerson = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $colophon -Name "publisher_person")
        $contact = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $colophon -Name "contact")
        $copyrightYear = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $colophon -Name "copyright_year")
        $copyrightHolder = Convert-PandocMetaToText (Get-PandocMetaProperty -Container $colophon -Name "copyright_holder")

        $masterText = [System.IO.File]::ReadAllText($MasterFile)
        if ($masterText -match '(?m)^:::\s*\{\.colophon\}\s*$') {
            Write-WarningMessage "99_master.mdには既に奥付があります。二重追加を避けるため追記しません。"
            return
        }

        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('::: {.colophon}')
        $lines.Add('')
        $lines.Add(("**書名：** {0}" -f $title))
        $lines.Add('')

        if (-not [string]::IsNullOrWhiteSpace($subtitle)) {
            $lines.Add(("**副題：** {0}" -f $subtitle))
            $lines.Add('')
        }

        $lines.Add(("**発行日：** {0}" -f $localizedDate))
        $lines.Add('')

        if (-not [string]::IsNullOrWhiteSpace($edition)) {
            $lines.Add(("**版：** {0}" -f $edition))
            $lines.Add('')
        }

        if (-not [string]::IsNullOrWhiteSpace($printing)) {
            $lines.Add(("**刷：** {0}" -f $printing))
            $lines.Add('')
        }

        $lines.Add(("**著者：** {0}" -f $author))
        $lines.Add('')

        if (-not [string]::IsNullOrWhiteSpace($publisher)) {
            $lines.Add(("**発行所：** {0}" -f $publisher))
            $lines.Add('')
        }

        if (-not [string]::IsNullOrWhiteSpace($publisherPerson)) {
            $lines.Add(("**発行人：** {0}" -f $publisherPerson))
            $lines.Add('')
        }

        if (-not [string]::IsNullOrWhiteSpace($contact)) {
            $lines.Add(("**連絡先：** {0}" -f $contact))
            $lines.Add('')
        }

        $copyrightText = Get-ColophonCopyrightText `
            -Rights $rights `
            -PublicationDate $dateText `
            -CopyrightYear $copyrightYear `
            -CopyrightHolder $copyrightHolder `
            -Author $author

        if (-not [string]::IsNullOrWhiteSpace($copyrightText)) {
            $lines.Add($copyrightText)
            $lines.Add('')
        }

        $lines.Add(':::')
        $lines.Add('')

        $colophonMarkdown = $lines -join [Environment]::NewLine
        $updatedMaster = $masterText.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $colophonMarkdown
        $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($MasterFile, $updatedMaster, $utf8WithoutBom)

        Write-Success "99_master.mdの末尾へ奥付を追加しました: $MasterFile"
    }
    finally {
        Remove-TemporaryFileSafely -Path $metadataJsonFile
    }
}

function Add-UnnumberedAttributeToFrontBackMatter {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    # 完成した99_master.mdを先頭から順に確認する。
    # 「はじめに」は章番号なしとする。
    # 「おわりに」自身と、それ以降に現れるすべての見出しを
    # 後付として番号なしにする。
    # fenced code block内の見出し文字列は対象外とする。

    $normalizedContent = $Content.Replace("`r`n", "`n").Replace("`r", "`n")

    # Windows PowerShell 5.1との互換性を優先し、
    # -split の負のMax-substrings指定は使用しない。
    $lines = [System.Text.RegularExpressions.Regex]::Split(
        $normalizedContent,
        "`n"
    )

    $afterOutro = $false
    $insideFence = $false
    $fenceMarker = ""
    $introFound = $false
    $outroFound = $false
    $updatedCount = 0
    $postOutroHeadingCount = 0

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]

        if ($line -match '^[ \t]*(?<fence>`{3,}|~{3,})') {
            $currentFence = $Matches['fence']

            if (-not $insideFence) {
                $insideFence = $true
                $fenceMarker = $currentFence.Substring(0, 1)
            }
            elseif ($currentFence.StartsWith($fenceMarker)) {
                $insideFence = $false
                $fenceMarker = ""
            }

            continue
        }

        if ($insideFence) {
            continue
        }

        # ATX形式の見出しを対象にする。
        # 行頭のUTF-8 BOMが文字として残っている場合にも対応する。
        if ($line -notmatch '^\uFEFF?(?<marks>#{1,6})[ \t]+(?<body>.+?)[ \t]*$') {
            continue
        }

        $headingMarks = $Matches['marks']
        $headingLevel = $headingMarks.Length
        $body = $Matches['body'].Trim()
        $title = $body
        $attributes = ""

        # 行末のPandoc属性を見出し本文から分離する。
        if ($body -match '^(?<title>.*?)[ \t]+(?<attributes>\{[^}\r\n]*\})$') {
            $title = $Matches['title'].Trim()
            $attributes = $Matches['attributes']
        }

        $heading = $headingMarks + ' ' + $title

        if ($headingLevel -eq 1 -and $title -eq 'はじめに') {
            $introFound = $true
        }

        if ($headingLevel -eq 1 -and $title -eq 'おわりに') {
            $outroFound = $true
            $afterOutro = $true
        }

        $shouldBeUnnumbered = (
            ($headingLevel -eq 1 -and $title -eq 'はじめに') -or
            $afterOutro
        )

        if (-not $shouldBeUnnumbered) {
            continue
        }

        if ($afterOutro) {
            $postOutroHeadingCount++
        }

        if ([string]::IsNullOrWhiteSpace($attributes)) {
            $lines[$index] = $heading + ' {.unnumbered}'
            $updatedCount++
            continue
        }

        if ($attributes -match '(?<!\S)\.unnumbered(?!\S)') {
            $lines[$index] = $heading + ' ' + $attributes
            continue
        }

        $attributeBody = $attributes.Substring(
            0,
            $attributes.Length - 1
        ).TrimEnd()

        $lines[$index] = $heading + ' ' + $attributeBody + ' .unnumbered}'
        $updatedCount++
    }

    return [pscustomobject]@{
        Content                 = ($lines -join [Environment]::NewLine)
        IntroFound              = $introFound
        OutroFound              = $outroFound
        UpdatedCount            = $updatedCount
        PostOutroHeadingCount   = $postOutroHeadingCount
    }
}

function Get-NormalizedMarkdownForMerge {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    # 入力ファイルごとに異なる可能性がある改行コードを一度LFへ統一する
    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n")

    # ファイル末尾の改行だけを取り除く
    # 行末の半角スペースなど、Markdownとして意味を持つ本文側の文字は残す
    $normalized = $normalized.TrimEnd([char[]]@("`n"))

    # 出力先OSの標準改行コードへ戻す
    return $normalized.Replace("`n", [Environment]::NewLine)
}

function Update-Master {
    Ensure-Directories
    Assert-ChapterFiles

    Write-Info "章ファイルを結合しています。"

    $builder = New-Object System.Text.StringBuilder
    $chapterPaths = @(Get-ChapterPaths)

    for ($index = 0; $index -lt $chapterPaths.Count; $index++) {
        $chapterPath = $chapterPaths[$index]
        Write-Host "       + $(Split-Path $chapterPath -Leaf)"

        $content = [System.IO.File]::ReadAllText($chapterPath)
        $normalizedContent = Get-NormalizedMarkdownForMerge -Content $content

        [void]$builder.Append($normalizedContent)

        # 各Markdownの境界には必ず改行コードを2個入れる
        # これにより、前ファイル末尾に改行がなくても次ファイルの見出しと連結しない
        [void]$builder.Append([Environment]::NewLine)
        [void]$builder.Append([Environment]::NewLine)
    }

    # 完成したmaster上で、前付と後付の見出し属性を統一する
    $frontBackMatterResult = Add-UnnumberedAttributeToFrontBackMatter `
        -Content $builder.ToString()

    $masterContent = $frontBackMatterResult.Content

    # Windows PowerShell 5.1でも文字化けしにくいUTF-8 BOMなしで保存する
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText(
        $MasterFile,
        $masterContent,
        $utf8WithoutBom
    )

    if (-not $frontBackMatterResult.IntroFound) {
        Write-WarningMessage "第1階層見出し『はじめに』が見つかりませんでした。"
    }

    if (-not $frontBackMatterResult.OutroFound) {
        Write-WarningMessage "第1階層見出し『おわりに』が見つかりませんでした。後続見出しの章番号なし設定は行われません。"
    }
    else {
        Write-Info (
            "『おわりに』以降の見出しを番号なしとして認識しました: {0}件" -f
            $frontBackMatterResult.PostOutroHeadingCount
        )
    }

    if ($frontBackMatterResult.UpdatedCount -eq 0 -and
        $frontBackMatterResult.IntroFound -and
        $frontBackMatterResult.OutroFound) {

        Write-Info "前付と後付の見出しには、既に章番号なし属性が設定されています。"
    }

    if ($frontBackMatterResult.IntroFound -and
        $frontBackMatterResult.OutroFound) {

        Write-Success "99_master.mdの『はじめに』と、『おわりに』以降の全見出しへ番号なし属性を設定しました。"
    }
    elseif ($frontBackMatterResult.IntroFound) {
        Write-WarningMessage "『はじめに』は設定しましたが、『おわりに』以降の後付設定は確認できませんでした。"
    }
    elseif ($frontBackMatterResult.OutroFound) {
        Write-WarningMessage "『おわりに』以降は設定しましたが、『はじめに』は確認できませんでした。"
    }
    else {
        Write-WarningMessage "前付と後付の章番号なし設定を確認できませんでした。"
    }

    Add-ColophonToMaster

    $masterSize = (Get-Item -LiteralPath $MasterFile).Length
    Write-Success "99_master.mdを更新しました: $MasterFile"
    Write-Host "       ファイルサイズ: $masterSize bytes"
    Write-MermaidMasterStatus -InputFile $MasterFile
}

function Assert-Command {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,
        [Parameter(Mandatory = $true)]
        [string]$InstallHint
    )

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue

    if ($null -eq $command) {
        throw "$CommandName が見つかりません。$InstallHint"
    }

    Write-Success "$CommandName を確認しました: $($command.Source)"
}


function Get-MermaidBlockCount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputFile
    )

    if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
        return 0
    }

    $content = [System.IO.File]::ReadAllText($InputFile)
    $lines = [regex]::Split($content, '\r?\n')
    $count = 0
    $index = 0
    $literalFenceCharacter = ""
    $literalFenceLength = 0

    while ($index -lt $lines.Count) {
        $line = $lines[$index]

        # 別のコードフェンス内にある```mermaidは説明用コードとして数えない。
        if (-not [string]::IsNullOrEmpty($literalFenceCharacter)) {
            $closingPattern = '^[ \t]*' +
                [regex]::Escape($literalFenceCharacter) +
                '{' + $literalFenceLength + ',}[ \t]*$'

            if ($line -match $closingPattern) {
                $literalFenceCharacter = ""
                $literalFenceLength = 0
            }

            $index++
            continue
        }

        # fenced code blockは ```markdown のように、
        # フェンス直後へ言語名を書く記法も正しく認識する。
        $fenceMatch = [regex]::Match(
            $line,
            '^[ \t]*(?<fence>`{3,}|~{3,})(?<info>.*)$'
        )

        if (-not $fenceMatch.Success) {
            $index++
            continue
        }

        $openingFence = $fenceMatch.Groups['fence'].Value
        $fenceCharacter = $openingFence.Substring(0, 1)
        $minimumFenceLength = $openingFence.Length
        $info = $fenceMatch.Groups['info'].Value.Trim()

        if ($info -eq "mermaid") {
            $count++
            $index++

            while ($index -lt $lines.Count) {
                $closingPattern = '^[ \t]*' +
                    [regex]::Escape($fenceCharacter) +
                    '{' + $minimumFenceLength + ',}[ \t]*$'

                if ($lines[$index] -match $closingPattern) {
                    $index++
                    break
                }

                $index++
            }

            continue
        }

        # Mermaid以外のfenced code blockは、閉じフェンスまで解析対象外にする。
        $literalFenceCharacter = $fenceCharacter
        $literalFenceLength = $minimumFenceLength
        $index++
    }

    return $count
}

function Write-MermaidMasterStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputFile
    )

    $count = Get-MermaidBlockCount -InputFile $InputFile
    Write-Info ("Mermaidコードブロック検出数: {0} / master" -f $count)

    if ($count -eq 0) {
        return
    }

    $command = Get-Command "mmdc" -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        Write-WarningMessage @"
Mermaid図を$count件検出しましたが、mmdcが見つかりません。
99_master.mdは生成しました。PDF、EPUB、DOCXの生成前に次を実行してください。
  npm install -g @mermaid-js/mermaid-cli
"@
        return
    }

    Write-Success ("Mermaid CLIを確認しました: {0}" -f $command.Source)
}

function Assert-RequiredProjectFiles {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("epub", "pdf", "docx")]
        [string[]]$Formats
    )

    $requiredFiles = @(
        $MetadataFile,
        $HeadingNumberFilterFile,
        $PageBreakFilterFile,
        $TableCaptionFilterFile,
        $CodePlainFilterFile,
        (Join-Path $StyleDir "br.lua")
    )

    foreach ($format in $Formats) {
        $requiredFiles += Join-Path $ConfigDir ("{0}.yaml" -f $format)
    }

    if ($Formats -contains "pdf") {
        $requiredFiles += @(
            (Join-Path $StyleDir "pdf-header.tex"),
            (Join-Path $StyleDir "table.lua"),
            $ColophonFilterFile
        )
    }

    $missingFiles = @(
        $requiredFiles |
        Sort-Object -Unique |
        Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }
    )

    if ($missingFiles.Count -gt 0) {
        $relativePaths = $missingFiles | ForEach-Object {
            try {
                [System.IO.Path]::GetRelativePath($ProjectRoot, $_)
            }
            catch {
                $_
            }
        }

        throw (
            "出力に必要な設定ファイルが不足しています。70_templateを確認し、treeを実行してください。`n  {0}" -f
            ($relativePaths -join "`n  ")
        )
    }
}


function Assert-ExportPrerequisites {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("epub", "pdf", "docx")]
        [string[]]$Formats,

        [Parameter(Mandatory = $true)]
        [string]$InputFile
    )

    Assert-RequiredProjectFiles -Formats $Formats

    Assert-Command `
        -CommandName "pandoc" `
        -InstallHint "winget install --id JohnMacFarlane.Pandoc --exact を実行してください。"

    if ($Formats -contains "pdf") {
        Assert-Command `
            -CommandName "lualatex" `
            -InstallHint "MiKTeXを導入し、MiKTeX Consoleで更新を完了してください。"
    }

    $mermaidCount = Get-MermaidBlockCount -InputFile $InputFile
    Write-Info ("Mermaidコードブロック検出数: {0} / 事前検査" -f $mermaidCount)

    if ($mermaidCount -eq 0) {
        Write-Info "Mermaid図がないため、mmdcは不要です。"
        return
    }

    $command = Get-Command "mmdc" -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw @"
Mermaid図を$mermaidCount件検出しましたが、Mermaid CLIのmmdcが見つかりません。
図を欠いた出力を防ぐため、Pandoc実行前に処理を中止します。
Node.jsを導入後、次を実行してください。
  npm install -g @mermaid-js/mermaid-cli
"@
    }

    Write-Success ("Mermaid CLIを確認しました: {0}" -f $command.Source)
}

function Get-MermaidCliPath {
    $command = Get-Command "mmdc" -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw @"
Mermaid CLIのmmdcが見つかりません。
Node.jsを導入後、次を実行してください。
  npm install -g @mermaid-js/mermaid-cli
"@
    }

    return $command.Source
}

function Get-TextSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hashBytes = $sha256.ComputeHash($bytes)
        return (($hashBytes | ForEach-Object { $_.ToString("x2") }) -join "")
    }
    finally {
        $sha256.Dispose()
    }
}

function Convert-ToMarkdownCaption {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return "　"
    }

    return $Text.Trim().Replace("\", "\\").Replace("[", "\[").Replace("]", "\]")
}

function Invoke-MermaidRender {
    param(
        [Parameter(Mandatory = $true)]
        [string]$MermaidCli,
        [Parameter(Mandatory = $true)]
        [string]$SourceFile,
        [Parameter(Mandatory = $true)]
        [string]$OutputFile,
        [switch]$Png
    )

    $arguments = @(
        "-i", $SourceFile,
        "-o", $OutputFile,
        "--backgroundColor", $(if ($Png) { "white" } else { "transparent" })
    )

    if ($Png) {
        $arguments += @("--scale", "2")
    }

    & $MermaidCli @arguments 2>&1 |
        ForEach-Object {
            Write-ExternalCommandOutput -CommandName "mmdc" -Message ([string]$_)
        }

    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Mermaid画像の生成に失敗しました。終了コード: $exitCode / 入力: $SourceFile"
    }

    if (-not (Test-Path -LiteralPath $OutputFile -PathType Leaf)) {
        throw "mmdcは終了しましたが、画像が生成されませんでした: $OutputFile"
    }
}

function Convert-MermaidBlocksForExport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputFile,
        [Parameter(Mandatory = $true)]
        [ValidateSet("epub", "pdf", "docx")]
        [string]$Format
    )

    $content = [System.IO.File]::ReadAllText($InputFile)

    # 入れ子のコードフェンス内にある```mermaidは説明用コードとして除外する。
    $mermaidCount = Get-MermaidBlockCount -InputFile $InputFile
    Write-Info ("Mermaidコードブロック検出数: {0} / 出力形式: {1}" -f $mermaidCount, $Format)

    if ($mermaidCount -eq 0) {
        Write-Info "トップレベルのMermaid図がないため、元の統合原稿をそのままPandocへ渡します。"
        return $InputFile
    }

    $mermaidCli = Get-MermaidCliPath
    Write-Info ("Mermaid CLIを使用します: {0}" -f $mermaidCli)
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    $lines = [regex]::Split($content, '\r?\n')
    $outputLines = New-Object System.Collections.Generic.List[string]
    $figureNumber = 0
    $index = 0
    $literalFenceCharacter = ""
    $literalFenceLength = 0

    while ($index -lt $lines.Count) {
        $line = $lines[$index]

        # 別のコードフェンス内では、mermaidという文字列を解析しない。
        if (-not [string]::IsNullOrEmpty($literalFenceCharacter)) {
            $outputLines.Add($line)

            $literalClosingPattern = '^[ \t]*' +
                [regex]::Escape($literalFenceCharacter) +
                '{' + $literalFenceLength + ',}[ \t]*$'

            if ($line -match $literalClosingPattern) {
                $literalFenceCharacter = ""
                $literalFenceLength = 0
            }

            $index++
            continue
        }

        # fenced code blockは ```markdown のように、
        # フェンス直後へ言語名を書く記法も正しく認識する。
        $fenceMatch = [regex]::Match(
            $line,
            '^[ \t]*(?<fence>`{3,}|~{3,})(?<info>.*)$'
        )

        if (-not $fenceMatch.Success) {
            $outputLines.Add($line)
            $index++
            continue
        }

        $openingFence = $fenceMatch.Groups['fence'].Value
        $fenceCharacter = $openingFence.Substring(0, 1)
        $minimumFenceLength = $openingFence.Length
        $info = $fenceMatch.Groups['info'].Value.Trim()

        if ($info -ne "mermaid") {
            $literalFenceCharacter = $fenceCharacter
            $literalFenceLength = $minimumFenceLength
            $outputLines.Add($line)
            $index++
            continue
        }

        $figureNumber++
        $blockLines = New-Object System.Collections.Generic.List[string]
        $index++
        $closed = $false

        while ($index -lt $lines.Count) {
            $candidate = $lines[$index]
            $closingPattern = '^[ \t]*' + [regex]::Escape($fenceCharacter) + '{' + $minimumFenceLength + ',}[ \t]*$'
            if ($candidate -match $closingPattern) {
                $closed = $true
                $index++
                break
            }

            $blockLines.Add($candidate)
            $index++
        }

        if (-not $closed) {
            throw "Mermaidコードフェンスが閉じられていません。図の出現順: $figureNumber"
        }

        $mermaidText = ($blockLines -join "`n").TrimEnd() + "`n"
        if ([string]::IsNullOrWhiteSpace($mermaidText)) {
            throw "Mermaidコードブロックが空です。図の出現順: $figureNumber"
        }

        # Mermaid公式のYAMLフロントマターからtitleを取得する。
        # 保存用.mmdには原文を残し、描画用コードからはtitleだけを除外する。
        $yamlTitle = ""
        $commentTitle = ""
        $bookWidth = ""
        $renderLines = New-Object System.Collections.Generic.List[string]
        foreach ($blockLine in $blockLines) {
            $renderLines.Add($blockLine)
        }

        $frontMatterStart = -1
        $frontMatterEnd = -1
        if ($renderLines.Count -gt 0 -and $renderLines[0] -match '^[ \t]*---[ \t]*$') {
            $frontMatterStart = 0
            for ($frontIndex = 1; $frontIndex -lt $renderLines.Count; $frontIndex++) {
                if ($renderLines[$frontIndex] -match '^[ \t]*---[ \t]*$') {
                    $frontMatterEnd = $frontIndex
                    break
                }
            }

            if ($frontMatterEnd -lt 0) {
                throw "MermaidのYAMLフロントマターが閉じられていません。図の出現順: $figureNumber"
            }

            $titleLineIndexes = New-Object System.Collections.Generic.List[int]
            for ($frontIndex = 1; $frontIndex -lt $frontMatterEnd; $frontIndex++) {
                $yamlTitleMatch = [regex]::Match(
                    $renderLines[$frontIndex],
                    '^[ \t]*title[ \t]*:[ \t]*(?<title>.*?)[ \t]*$'
                )
                if ($yamlTitleMatch.Success) {
                    if ([string]::IsNullOrWhiteSpace($yamlTitle)) {
                        $yamlTitle = $yamlTitleMatch.Groups['title'].Value.Trim()
                        if (($yamlTitle.StartsWith('"') -and $yamlTitle.EndsWith('"')) -or
                            ($yamlTitle.StartsWith("'") -and $yamlTitle.EndsWith("'"))) {
                            $yamlTitle = $yamlTitle.Substring(1, $yamlTitle.Length - 2)
                        }
                    }
                    $titleLineIndexes.Add($frontIndex)
                }
            }

            for ($removeIndex = $titleLineIndexes.Count - 1; $removeIndex -ge 0; $removeIndex--) {
                $renderLines.RemoveAt($titleLineIndexes[$removeIndex])
                $frontMatterEnd--
            }

            # titleしかなかった場合は、空になったフロントマター自体を描画用コードから外す。
            $hasRemainingFrontMatter = $false
            for ($frontIndex = 1; $frontIndex -lt $frontMatterEnd; $frontIndex++) {
                if (-not [string]::IsNullOrWhiteSpace($renderLines[$frontIndex]) -and
                    $renderLines[$frontIndex] -notmatch '^[ \t]*#') {
                    $hasRemainingFrontMatter = $true
                    break
                }
            }
            if (-not $hasRemainingFrontMatter) {
                $renderLines.RemoveAt($frontMatterEnd)
                $renderLines.RemoveAt($frontMatterStart)
            }
        }

        # 0.2.9までの独自形式を移行期間中だけ読み取る。
        for ($commentIndex = 0; $commentIndex -lt $blockLines.Count; $commentIndex++) {
            $commentTitleMatch = [regex]::Match(
                $blockLines[$commentIndex],
                '^[ \t]*%%[ \t]*title[ \t]*:[ \t]*(?<title>.+?)[ \t]*$'
            )
            if ($commentTitleMatch.Success) {
                $commentTitle = $commentTitleMatch.Groups['title'].Value.Trim()
                break
            }
        }

        # PDF紙面上の個別幅はMermaidコメントで指定する。
        # Mermaid自身の描画設定と混同しないよう、EPUBとDOCXでは使用しない。
        $bookWidthCount = 0
        for ($commentIndex = 0; $commentIndex -lt $blockLines.Count; $commentIndex++) {
            $bookWidthLine = $blockLines[$commentIndex]
            if ($bookWidthLine -notmatch '^[ \t]*%%[ \t]*book-width[ \t]*:') {
                continue
            }

            $bookWidthCount++
            $bookWidthMatch = [regex]::Match(
                $bookWidthLine,
                '^[ \t]*%%[ \t]*book-width[ \t]*:[ \t]*(?<width>[0-9]{1,3})%[ \t]*$'
            )
            if (-not $bookWidthMatch.Success) {
                throw "Mermaid図$figureNumberのbook-widthが不正です。1%から100%までの割合で指定してください。例: %% book-width: 45%"
            }

            $bookWidthNumber = [int]$bookWidthMatch.Groups['width'].Value
            if ($bookWidthNumber -lt 1 -or $bookWidthNumber -gt 100) {
                throw "Mermaid図$figureNumberのbook-widthが範囲外です。1%から100%までで指定してください。"
            }

            $bookWidth = "{0}%" -f $bookWidthNumber
        }

        if ($bookWidthCount -gt 1) {
            throw "Mermaid図$figureNumberにbook-widthが複数あります。指定は1件だけにしてください。"
        }

        $title = if (-not [string]::IsNullOrWhiteSpace($yamlTitle)) {
            $yamlTitle
        }
        else {
            $commentTitle
        }

        if (-not [string]::IsNullOrWhiteSpace($yamlTitle) -and
            -not [string]::IsNullOrWhiteSpace($commentTitle)) {
            if ($yamlTitle -eq $commentTitle) {
                Write-WarningMessage "Mermaid図$figureNumberにYAML titleと旧%% title:が重複しています。YAML titleを採用します。"
            }
            else {
                Write-WarningMessage "Mermaid図$figureNumberのYAML titleと旧%% title:が一致しません。YAML titleを採用します。"
            }
        }
        elseif ([string]::IsNullOrWhiteSpace($yamlTitle) -and
                -not [string]::IsNullOrWhiteSpace($commentTitle)) {
            Write-WarningMessage "Mermaid図$figureNumberは旧%% title:形式です。今後はYAMLフロントマターのtitleを使用してください。"
        }
        elseif ([string]::IsNullOrWhiteSpace($title)) {
            Write-WarningMessage "Mermaid図$figureNumberにYAML titleがありません。図番号だけで出力します。"
        }

        $titleForLog = if ([string]::IsNullOrWhiteSpace($title)) { "（タイトルなし）" } else { $title }
        Write-Info ("Mermaid図{0}: title={1}" -f $figureNumber, $titleForLog)

        # 描画用コードから旧titleコメントと出版用の幅指定を外す。
        # その他のMermaidコメントは保持する。
        for ($renderIndex = $renderLines.Count - 1; $renderIndex -ge 0; $renderIndex--) {
            if ($renderLines[$renderIndex] -match '^[ \t]*%%[ \t]*(title|book-width)[ \t]*:') {
                $renderLines.RemoveAt($renderIndex)
            }
        }

        $renderText = ($renderLines -join "`n").TrimEnd() + "`n"
        if ([string]::IsNullOrWhiteSpace($renderText)) {
            throw "タイトル情報を除くとMermaid本体が空になります。図の出現順: $figureNumber"
        }

        # 描画に使うコードだけを画像キャッシュの判定対象にする。
        # titleとbook-widthを変更しても図形が同じなら既存画像を再利用する。
        # Mermaid本体やYAML configを変更した場合は新しい画像を生成する。
        $hashSource = "book-mermaid-v5`n" + $renderText
        $hash = (Get-TextSha256 -Text $hashSource).Substring(0, 16)
        $baseName = "fig_$hash"
        Write-Info ("Mermaid図{0}: asset={1}" -f $figureNumber, $baseName)
        $mmdFile = Join-Path $FigureDir "$baseName.mmd"
        $svgFile = Join-Path $FigureDir "$baseName.svg"
        $pngFile = Join-Path $FigureDir "$baseName.png"
        $renderFile = Join-Path $WorkDir "$baseName.render.mmd"

        if (-not (Test-Path -LiteralPath $mmdFile -PathType Leaf) -or
            [System.IO.File]::ReadAllText($mmdFile) -ne $mermaidText) {
            [System.IO.File]::WriteAllText($mmdFile, $mermaidText, $utf8WithoutBom)
            Write-Success "Mermaid元コードを保存しました: $mmdFile"
        }

        if (-not (Test-Path -LiteralPath $svgFile -PathType Leaf) -or
            -not (Test-Path -LiteralPath $pngFile -PathType Leaf)) {
            [System.IO.File]::WriteAllText($renderFile, $renderText, $utf8WithoutBom)
        }

        if (-not (Test-Path -LiteralPath $svgFile -PathType Leaf)) {
            Invoke-MermaidRender -MermaidCli $mermaidCli -SourceFile $renderFile -OutputFile $svgFile
            Write-Success "Mermaid SVGを生成しました: $svgFile"
        }
        else {
            Write-Info "既存のMermaid SVGを再利用します: $svgFile"
        }

        if (-not (Test-Path -LiteralPath $pngFile -PathType Leaf)) {
            Invoke-MermaidRender -MermaidCli $mermaidCli -SourceFile $renderFile -OutputFile $pngFile -Png
            Write-Success "Mermaid PNGを生成しました: $pngFile"
        }
        else {
            Write-Info "既存のMermaid PNGを再利用します: $pngFile"
        }

        $assetExtension = "png"
        $relativeAssetPath = "21_figure/$baseName.$assetExtension"
        $captionText = if ($Format -eq "pdf") {
            Convert-ToMarkdownCaption -Text $title
        }
        elseif ([string]::IsNullOrWhiteSpace($title)) {
            "図$figureNumber"
        }
        else {
            Convert-ToMarkdownCaption -Text ("図{0} {1}" -f $figureNumber, $title)
        }

        # Mermaid図だけに表示幅を設定する。
        # PDFではbook-widthがあれば個別幅、なければ標準幅75%を使用する。
        # EPUBとDOCXではbook-widthを無視し、幅75%だけを指定する。
        $imageAttributes = if ($Format -eq "pdf") {
            $pdfImageWidth = if ([string]::IsNullOrWhiteSpace($bookWidth)) {
                "75%"
            }
            else {
                $bookWidth
            }

            Write-Info ("Mermaid図{0}: PDF表示幅={1} / 縦横比を維持" -f $figureNumber, $pdfImageWidth)
            "#fig-{0} width={1}" -f $hash, $pdfImageWidth
        }
        else {
            if (-not [string]::IsNullOrWhiteSpace($bookWidth)) {
                Write-Info ("Mermaid図{0}: book-width={1}は{2}では使用せず、標準幅75%を適用します。" -f $figureNumber, $bookWidth, $Format)
            }
            "#fig-{0} width=75%" -f $hash
        }

        $outputLines.Add(("![{0}]({1}){{{2}}}" -f $captionText, $relativeAssetPath, $imageAttributes))
        $outputLines.Add("")
    }

    $preparedFile = Join-Path $WorkDir ("99_master_mermaid_{0}.md" -f $Format)
    [System.IO.File]::WriteAllText(
        $preparedFile,
        (($outputLines -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine),
        $utf8WithoutBom
    )

    Write-Success "Mermaid図を画像参照へ置換した作業用Markdownを生成しました: $preparedFile"
    return $preparedFile
}

function Test-Environment {
    Write-Info ("実行中のbook.ps1: version {0} / {1}" -f $BookScriptVersion, $PSCommandPath)
    Ensure-Directories
    Assert-ChapterFiles

    Write-Info "原稿ファイルを確認しました。"

    Assert-Command `
        -CommandName "pandoc" `
        -InstallHint "winget install --id JohnMacFarlane.Pandoc --exact を実行してください。"

    $mermaidCommand = Get-Command "mmdc" -ErrorAction SilentlyContinue
    if ($null -eq $mermaidCommand) {
        Write-WarningMessage "mmdcが見つかりません。Mermaid図を含む原稿の出力には@mermaid-js/mermaid-cliが必要です。"
    }
    else {
        Write-Success ("Mermaid CLIを確認しました: {0}" -f $mermaidCommand.Source)
    }

    # PDFを作らない場合でも、出版環境の確認として存在を報告する
    $luaLatex = Get-Command "lualatex" -ErrorAction SilentlyContinue
    if ($null -eq $luaLatex) {
        Write-WarningMessage "lualatex が見つかりません。PDF生成時にはMiKTeXが必要です。"
    }
    else {
        Write-Success ("lualatex を確認しました: {0}" -f $luaLatex.Source)
    }

    $epubConfigFile = Join-Path $ConfigDir "epub.yaml"
    $pdfConfigFile = Join-Path $ConfigDir "pdf.yaml"
    $metadataFile = $MetadataFile

    if (Test-Path -LiteralPath $epubConfigFile -PathType Leaf) {
        $epubConfigText = Get-Content -LiteralPath $epubConfigFile -Raw

        if ($epubConfigText -match 'metadata-file:\s*config/metadata\.yaml') {
            Write-WarningMessage "epub.yamlに旧パスが残っています。metadata-fileを50_config/metadata.yamlへ変更してください。"
        }
        elseif ($epubConfigText -match 'metadata-file:\s*50_config/metadata\.yaml') {
            Write-Success "epub.yamlのmetadata-fileを確認しました。"
        }
        else {
            Write-WarningMessage "epub.yamlでmetadata-fileの指定を確認できませんでした。"
        }
    }
    else {
        Write-WarningMessage ("epub.yamlが見つかりません: {0}" -f $epubConfigFile)
    }

    if (Test-Path -LiteralPath $metadataFile -PathType Leaf) {
        Write-Success ("metadata.yamlを確認しました: {0}" -f $metadataFile)
    }
    else {
        Write-WarningMessage ("metadata.yamlが見つかりません: {0}" -f $metadataFile)
    }
    if (Test-Path -LiteralPath $pdfConfigFile -PathType Leaf) {
        $pdfConfigText = Get-Content -LiteralPath $pdfConfigFile -Raw

        if ($pdfConfigText -match 'metadata-file:\s*config/metadata\.yaml') {
            Write-WarningMessage "pdf.yamlに旧パスが残っています。metadata-fileを50_config/metadata.yamlへ変更してください。"
        }
        else {
            Write-Success ("pdf.yamlを確認しました: {0}" -f $pdfConfigFile)
        }

        if ($pdfConfigText -match 'CJKmainfont:\s*Yu Mincho') {
            Write-Success "PDF用の日本語本文フォントを確認しました: Yu Mincho"
        }
        else {
            Write-WarningMessage "pdf.yamlにCJKmainfontの指定がありません。日本語PDFで文字欠けが起きる可能性があります。"
        }

        if ($pdfConfigText -match '(?m)^\s*-\s*a4paper\s*$') {
            Write-Success "PDF用紙サイズを確認しました: A4"
        }
        else {
            Write-WarningMessage "pdf.yamlにa4paperの指定がありません。"
        }

        if ($pdfConfigText -match '(?m)^\s*-\s*12pt\s*$') {
            Write-Success "PDF文字サイズを確認しました: 12pt"
        }
        else {
            Write-WarningMessage "pdf.yamlの文字サイズが12ptではありません。"
        }

        if ($pdfConfigText -match '(?m)^top-level-division:\s*chapter\s*$') {
            Write-Success "Markdownの「# 見出し」を書籍の章として扱う設定を確認しました。"
        }
        else {
            Write-WarningMessage "pdf.yamlにtop-level-division: chapterの指定がありません。章の改ページとヘッダー表示が崩れる可能性があります。"
        }

        if (
            $pdfConfigText -match 'top=23mm' -and
            $pdfConfigText -match 'bottom=19mm' -and
            $pdfConfigText -match 'left=23mm' -and
            $pdfConfigText -match 'right=23mm'
        ) {
            Write-Success "PDF余白を確認しました: 上23mm、下19mm、左右23mm"
        }
        else {
            Write-WarningMessage "pdf.yamlの余白設定が上23mm、下19mm、左右23mmではありません。"
        }

        $pdfHeaderFile = Join-Path $StyleDir "pdf-header.tex"

        if ($pdfConfigText -match '60_style/pdf-header\.tex') {
            Write-Success "PDFヘッダーファイルの参照を確認しました。"
        }
        else {
            Write-WarningMessage "pdf.yamlに60_style/pdf-header.texの参照がありません。"
        }

        if (Test-Path -LiteralPath $pdfHeaderFile -PathType Leaf) {
            $pdfHeaderText = Get-Content -LiteralPath $pdfHeaderFile -Raw

            if (
                $pdfHeaderText -match 'pdfpagemode=UseNone' -and
                $pdfHeaderText -match '/PageMode /UseNone'
            ) {
                Write-Success "PDFを開いたときにしおり欄を自動表示しない設定を確認しました。"
            }
            else {
                Write-WarningMessage "pdf-header.texにしおり欄の自動表示を抑止する設定がありません。"
            }

            if (
                $pdfHeaderText -match '\\@makechapterhead' -and
                $pdfHeaderText -match '\\vspace\*\{-10pt\}' -and
                $pdfHeaderText -match '\\bfseries\\Large' -and
                $pdfHeaderText -match '第\\thechapter\s*章'
            ) {
                Write-Success "PDF章見出しの章番号、上位置、文字サイズを確認しました。"
            }
            else {
                Write-WarningMessage "pdf-header.texに章番号表示、余白、またはサイズ設定がありません。"
            }

            if (
                $pdfHeaderText -match '\\counterwithout\{figure\}\{chapter\}' -and
                $pdfHeaderText -match '\\renewcommand\{\\thefigure\}\{\\arabic\{figure\}\}'
            ) {
                Write-Success "PDF図番号を章をまたぐ連番にする設定を確認しました。"
            }
            else {
                Write-WarningMessage "pdf-header.texに図番号の通し番号設定がありません。"
            }

            if (
                $pdfHeaderText -match '\\captionsetup\[figure\]' -and
                $pdfHeaderText -match 'position=bottom' -and
                $pdfHeaderText -match 'font=normalsize' -and
                $pdfHeaderText -match 'name=図'
            ) {
                Write-Success "PDF図キャプションの下配置、本文相当サイズ、名称設定を確認しました。"
            }
            else {
                Write-WarningMessage "pdf-header.texに図キャプションの位置または文字サイズ設定がありません。"
            }

            if ($pdfHeaderText.Contains('\sffamily\originalmaketitle')) {
                Write-Success "PDFタイトル面のゴシック体設定を確認しました。"
            }
            else {
                Write-WarningMessage "pdf-header.texにタイトル面のゴシック体設定がありません。"
            }

            if ($pdfHeaderText -match '\\usepackage\{needspace\}') {
                Write-Success "PDF表の改ページ抑止に必要なneedspaceパッケージを確認しました。"
            }
            else {
                Write-WarningMessage "pdf-header.texにneedspaceパッケージの読み込みがありません。"
            }

            if (
                $pdfHeaderText -match '\\definecolor\{bookcodebackground\}\{RGB\}\{245,245,245\}' -and
                $pdfHeaderText -match '\\definecolor\{bookcodeborder\}\{RGB\}\{153,153,153\}' -and
                $pdfHeaderText -match 'fboxrule=0\.6pt' -and
                $pdfHeaderText -match 'framerule=0\.6pt'
            ) {
                Write-Success "PDFコードフェンスの薄いグレー背景、枠色、0.6pt枠線設定を確認しました。"
            }
            else {
                Write-WarningMessage "pdf-header.texのコードフェンス装飾が0.3.2仕様ではありません。"
            }

            if (
                $pdfHeaderText -match '\\newif\\ifbooktoc' -and
                $pdfHeaderText -match '\\def\\ps@bookchapter' -and
                $pdfHeaderText -match '\\gdef\\bookchaptertitle\{#1\}' -and
                $pdfHeaderText -match '\\thispagestyle\{bookchapter\}' -and
                $pdfHeaderText -match '\\hrule' -and
                $pdfHeaderText -match '\\thispagestyle\{bookfront\}'
            ) {
                Write-Success "目次の柱抑制と、章番号を含む章柱および横線設定を確認しました。"
            }
            else {
                Write-WarningMessage "目次または章開始ページ専用の柱設定が不足しています。"
            }
        }
        else {
            Write-WarningMessage ("pdf-header.texが見つかりません: {0}" -f $pdfHeaderFile)
        }
    }
    else {
        Write-WarningMessage ("pdf.yamlが見つかりません: {0}" -f $pdfConfigFile)
    }

    $brFilterFile = Join-Path $StyleDir "br.lua"

    if (Test-Path -LiteralPath $brFilterFile -PathType Leaf) {
        $brFilterText = Get-Content -LiteralPath $brFilterFile -Raw

        if (
            $brFilterText -match 'function\s+RawInline' -and
            $brFilterText -match 'pandoc\.LineBreak'
        ) {
            Write-Success "br.luaによるHTML改行変換を確認しました。"
        }
        else {
            Write-WarningMessage "br.luaは存在しますが、RawInlineからLineBreakへの変換を確認できません。"
        }
    }
    else {
        Write-WarningMessage ("br.luaが見つかりません: {0}" -f $brFilterFile)
    }

    $tableFilterFile = Join-Path $StyleDir "table.lua"

    if (Test-Path -LiteralPath $tableFilterFile -PathType Leaf) {
        $tableFilterText = Get-Content -LiteralPath $tableFilterFile -Raw

        if (
            $tableFilterText -match 'function\s+Table' -and
            $tableFilterText -match 'Needspace' -and
            $tableFilterText -match '0\.70' -and
            $tableFilterText -match 'column_count' -and
            $tableFilterText -match 'booktablerule' -and
            $tableFilterText -match '0\.25pt'
        ) {
            Write-Success "table.luaによるPDF表の配置補助と、3列以上の行間横罫線設定を確認しました。"
        }
        else {
            Write-WarningMessage "table.luaは存在しますが、PDF表の配置補助または3列以上の横罫線設定を確認できません。"
        }
    }
    else {
        Write-WarningMessage ("table.luaが見つかりません: {0}" -f $tableFilterFile)
    }
    if (Test-Path -LiteralPath $PageBreakFilterFile -PathType Leaf) {
        $pageBreakFilterText = Get-Content -LiteralPath $PageBreakFilterFile -Raw

        if (
            $pageBreakFilterText -match 'function\s+Div' -and
            $pageBreakFilterText -match 'pagebreak' -and
            $pageBreakFilterText -match 'clearpage' -and
            $pageBreakFilterText -match 'w:type="page"' -and
            $pageBreakFilterText -match 'break-before' -and
            $pageBreakFilterText -match '&#160;'
        ) {
            Write-Success "pagebreak.luaによるPDF、DOCX、EPUB共通の任意改ページ設定を確認しました。"
        }
        else {
            Write-WarningMessage "pagebreak.luaは存在しますが、出力形式別の改ページ処理を確認できません。"
        }
    }
    else {
        Write-WarningMessage ("pagebreak.luaが見つかりません: {0}" -f $PageBreakFilterFile)
    }
    if (Test-Path -LiteralPath $TableCaptionFilterFile -PathType Leaf) {
        $tableCaptionFilterText = Get-Content -LiteralPath $TableCaptionFilterFile -Raw

        if (
            $tableCaptionFilterText -match 'function\s+Table' -and
            $tableCaptionFilterText -match '表' -and
            $tableCaptionFilterText -match 'FORMAT:match\("latex"\)'
        ) {
            Write-Success "table-caption.luaによる表キャプションの連番設定を確認しました。"
        }
        else {
            Write-WarningMessage "table-caption.luaは存在しますが、表キャプション採番処理を確認できません。"
        }
    }
    else {
        Write-WarningMessage ("table-caption.luaが見つかりません: {0}" -f $TableCaptionFilterFile)
    }

    if (Test-Path -LiteralPath $CodePlainFilterFile -PathType Leaf) {
        $codePlainFilterText = Get-Content -LiteralPath $CodePlainFilterFile -Raw

        if (
            $codePlainFilterText -match 'function\s+CodeBlock' -and
            $codePlainFilterText -match 'markdown' -and
            $codePlainFilterText -match 'text'
        ) {
            Write-Success "code-plain.luaによるmarkdown/textコードフェンスの単色表示設定を確認しました。"
        }
        else {
            Write-WarningMessage "code-plain.luaは存在しますが、markdown/text単色表示処理を確認できません。"
        }
    }
    else {
        Write-WarningMessage ("code-plain.luaが見つかりません: {0}" -f $CodePlainFilterFile)
    }


    if (Test-Path -LiteralPath $HeadingNumberFilterFile -PathType Leaf) {
        $headingNumberFilterText = Get-Content -LiteralPath $HeadingNumberFilterFile -Raw

        if (
            $headingNumberFilterText -match 'function\s+Header' -and
            $headingNumberFilterText -match 'header\.level\s*>=\s*3' -and
            $headingNumberFilterText -match 'after_outro\s+or\s+header\.level' -and
            $headingNumberFilterText -match 'in_intro\s+and\s+header\.level\s*==\s*2' -and
            $headingNumberFilterText -match 'unnumbered'
        ) {
            Write-Success "本文では章と節だけに番号を付け、小見出しには番号を付けない設定を確認しました。"
            Write-Success "『はじめに』内の節を番号なしにする設定を確認しました。"
            Write-Success "『おわりに』以降の全見出しを番号なしにする設定を確認しました。"
            Write-Success "目次には章と節だけを掲載する設定を確認しました。"
        }
        else {
            Write-WarningMessage "heading-numbering.luaは存在しますが、見出し番号の階層制御を確認できません。"
        }
    }
    else {
        Write-WarningMessage ("heading-numbering.luaが見つかりません。treeタスクで初期作成できます: {0}" -f $HeadingNumberFilterFile)
    }


    if (Test-Path -LiteralPath $ColophonFilterFile -PathType Leaf) {
        $colophonFilterText = Get-Content -LiteralPath $ColophonFilterFile -Raw

        if (
            $colophonFilterText -match 'function\s+Div' -and
            $colophonFilterText -match 'colophon' -and
            $colophonFilterText -match 'vspace\*' -and
            $colophonFilterText -match 'thispagestyle\{empty\}'
        ) {
            Write-Success "colophon.luaによるPDF奥付の下部配置設定を確認しました。"
        }
        else {
            Write-WarningMessage "colophon.luaは存在しますが、奥付の下部配置処理を確認できません。"
        }
    }
    else {
        Write-WarningMessage ("colophon.luaが見つかりません。treeタスクで初期作成できます: {0}" -f $ColophonFilterFile)
    }

    Show-MetadataAndColophonPreview

    Write-Success "基本環境の確認が完了しました。"
}

function Invoke-PandocExport {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("epub", "pdf", "docx")]
        [string]$Format,

        [switch]$SkipMasterUpdate,
        [switch]$SkipPreflight
    )

    if (-not $SkipMasterUpdate) {
        Update-Master
    }

    if (-not $SkipPreflight) {
        Assert-ExportPrerequisites -Formats @($Format) -InputFile $MasterFile
    }

    $outputFile = Join-Path $PublishDir "$OutputBaseName.$Format"
    $defaultsFile = Join-Path $ConfigDir "$Format.yaml"
    $aspectRatioHeaderFile = Join-Path $WorkDir "book-image-aspect-ratio.tex"

    $brFilterFile = Join-Path $StyleDir "br.lua"
    $tableFilterFile = Join-Path $StyleDir "table.lua"
    $headingNumberFilterFile = $HeadingNumberFilterFile
    $pageBreakFilterFile = $PageBreakFilterFile
    $tableCaptionFilterFile = $TableCaptionFilterFile
    $codePlainFilterFile = $CodePlainFilterFile
    $colophonFilterFile = $ColophonFilterFile
    $pandocInputFile = Convert-MermaidBlocksForExport -InputFile $MasterFile -Format $Format
    $resourcePath = @($ProjectRoot, $ManuscriptDir, $FigureDir) -join [System.IO.Path]::PathSeparator

    $arguments = @(
        $pandocInputFile,
        "--standalone",
        "--output=$outputFile",
        "--resource-path=$resourcePath",
        "--number-sections",
        "--toc-depth=2",
        "--defaults=$defaultsFile",
        "--lua-filter=$headingNumberFilterFile",
        "--lua-filter=$pageBreakFilterFile",
        "--lua-filter=$tableCaptionFilterFile",
        "--lua-filter=$codePlainFilterFile",
        "--lua-filter=$brFilterFile"
    )

    if ($Format -eq "pdf") {
        $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText(
            $aspectRatioHeaderFile,
            "\AtBeginDocument{\setkeys{Gin}{keepaspectratio}}`n",
            $utf8WithoutBom
        )

        $arguments += "--include-in-header=$aspectRatioHeaderFile"
        $arguments += "--lua-filter=$tableFilterFile"
        $arguments += "--lua-filter=$colophonFilterFile"
        Write-Info "PDF画像の縦横比維持設定を追加しました。"
    }

    Write-Info "70_template由来の設定ファイルを使用します: $defaultsFile"

    Write-Info ("{0}を生成しています。" -f $Format)

    Push-Location -LiteralPath $ProjectRoot

    try {
        & pandoc @arguments 2>&1 |
            ForEach-Object {
                Write-ExternalCommandOutput `
                    -CommandName "pandoc" `
                    -Message ([string]$_)
            }

        $pandocExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if ($pandocExitCode -ne 0) {
        throw (
            "Pandocによる{0}生成に失敗しました。終了コード: {1}" -f
            $Format,
            $pandocExitCode
        )
    }

    if (-not (Test-Path -LiteralPath $outputFile -PathType Leaf)) {
        throw ("Pandocは終了しましたが、出力ファイルが見つかりません: {0}" -f $outputFile)
    }

    Write-Success ("{0}を生成しました: {1}" -f $Format, $outputFile)
}


function Get-ProjectRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $rootPath = [System.IO.Path]::GetFullPath($ProjectRoot)
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        $rootUri = [System.Uri]::new(($rootPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar))
        $fileUri = [System.Uri]::new($fullPath)
        $relativeUri = $rootUri.MakeRelativeUri($fileUri)
        return [System.Uri]::UnescapeDataString($relativeUri.ToString()).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    }
    catch {
        return $Path
    }
}

function Write-ConfigurationItem {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Required", "Recommended", "Optional")]
        [string]$Importance,

        [Parameter(Mandatory = $true)]
        [string]$IfMissing,

        [Parameter(Mandatory = $true)]
        [string]$UsedBy,

        [Parameter(Mandatory = $true)]
        [string]$Kind
    )

    $exists = Test-Path -LiteralPath $Path -PathType Leaf
    $status = if ($exists) { "Found" } else { "Not found" }

    Write-Host ("{0}:" -f $Label)
    Write-Host ("  Path: {0}" -f (Get-ProjectRelativePath -Path $Path))
    Write-Host ("  Status: {0}" -f $status)
    Write-Host ("  Importance: {0}" -f $Importance)
    Write-Host ("  If missing: {0}" -f $IfMissing)
    Write-Host ("  Used by: {0}" -f $UsedBy)
    Write-Host ("  Type: {0}" -f $Kind)
    Write-Host ""
}

function Show-BookConfiguration {
    Ensure-Directories

    $epubDefaults = Join-Path $ConfigDir "epub.yaml"
    $pdfDefaults = Join-Path $ConfigDir "pdf.yaml"
    $docxDefaults = Join-Path $ConfigDir "docx.yaml"
    $pdfHeader = Join-Path $StyleDir "pdf-header.tex"
    $epubCss = Join-Path $StyleDir "epub.css"
    $brFilter = Join-Path $StyleDir "br.lua"
    $tableFilter = Join-Path $StyleDir "table.lua"
    $tableCaptionFilter = $TableCaptionFilterFile
    $codePlainFilter = $CodePlainFilterFile

    $items = @(
        @{
            Label = "Metadata"
            Path = $MetadataFile
            Importance = "Required"
            IfMissing = "The build stops because book metadata is required"
            UsedBy = "PDF, EPUB, DOCX"
            Kind = "handwritten source"
        },
        @{
            Label = "EPUB defaults"
            Path = $epubDefaults
            Importance = "Required"
            IfMissing = "Export stops until the canonical file is restored from 70_template"
            UsedBy = "EPUB"
            Kind = "Pandoc defaults"
        },
        @{
            Label = "PDF defaults"
            Path = $pdfDefaults
            Importance = "Required"
            IfMissing = "Export stops until the canonical file is restored from 70_template"
            UsedBy = "PDF"
            Kind = "Pandoc defaults"
        },
        @{
            Label = "DOCX defaults"
            Path = $docxDefaults
            Importance = "Required"
            IfMissing = "Export stops until the canonical file is restored from 70_template"
            UsedBy = "DOCX"
            Kind = "Pandoc defaults"
        },
        @{
            Label = "PDF header"
            Path = $pdfHeader
            Importance = "Required"
            IfMissing = "Export stops until the canonical file is restored from 70_template"
            UsedBy = "PDF"
            Kind = "LaTeX header"
        },
        @{
            Label = "EPUB stylesheet"
            Path = $epubCss
            Importance = "Optional"
            IfMissing = "EPUB uses its default styling unless epub.yaml references this file"
            UsedBy = "EPUB when referenced by epub.yaml"
            Kind = "CSS stylesheet"
        },
        @{
            Label = "Heading numbering filter"
            Path = $HeadingNumberFilterFile
            Importance = "Required"
            IfMissing = "Export stops until the canonical file is restored from 70_template"
            UsedBy = "PDF, EPUB, DOCX"
            Kind = "Lua filter"
        },
        @{
            Label = "Table caption filter"
            Path = $tableCaptionFilter
            Importance = "Required"
            IfMissing = "Export stops until the canonical file is restored from 70_template"
            UsedBy = "PDF, EPUB, DOCX"
            Kind = "Lua filter"
        },
        @{
            Label = "Plain markdown/text code filter"
            Path = $codePlainFilter
            Importance = "Required"
            IfMissing = "Export stops until the canonical file is restored from 70_template"
            UsedBy = "PDF, EPUB, DOCX"
            Kind = "Lua filter"
        },
        @{
            Label = "Line break filter"
            Path = $brFilter
            Importance = "Required"
            IfMissing = "Export stops until the canonical file is restored from 70_template"
            UsedBy = "PDF, EPUB, DOCX"
            Kind = "Lua filter"
        },
        @{
            Label = "Table pagination filter"
            Path = $tableFilter
            Importance = "Required"
            IfMissing = "Export stops until the canonical file is restored from 70_template"
            UsedBy = "PDF"
            Kind = "Lua filter"
        },
        @{
            Label = "Colophon filter"
            Path = $ColophonFilterFile
            Importance = "Required"
            IfMissing = "Export stops until the canonical file is restored from 70_template"
            UsedBy = "PDF"
            Kind = "Lua filter"
        }
    )

    Write-Host ""
    Write-Host "[Project configuration]"
    Write-Host ("Script version: {0}" -f $BookScriptVersion)
    Write-Host ("Project root: {0}" -f $ProjectRoot)
    Write-Host ""

    foreach ($item in $items) {
        Write-ConfigurationItem @item
    }

    $mermaidCli = Get-MermaidCliPath
    Write-Host "Mermaid:"
    Write-Host ("  Command: {0}" -f $(if ($null -ne $mermaidCli) { $mermaidCli } else { "mmdc" }))
    Write-Host ("  Status: {0}" -f $(if ($null -ne $mermaidCli) { "Available" } else { "Not found" }))
    Write-Host ("  Asset directory: {0}" -f (Get-ProjectRelativePath -Path $FigureDir))
    Write-Host ""

    Write-Host "Directories:"
    Write-Host ("  Manuscript: {0}" -f (Get-ProjectRelativePath -Path $ManuscriptDir))
    Write-Host ("  Figures: {0}" -f (Get-ProjectRelativePath -Path $FigureDir))
    Write-Host ("  Work: {0}" -f (Get-ProjectRelativePath -Path $WorkDir))
    Write-Host ("  Publish: {0}" -f (Get-ProjectRelativePath -Path $PublishDir))
    Write-Host ""

    $knownPaths = @($items | ForEach-Object { [System.IO.Path]::GetFullPath($_.Path) })
    $candidateFiles = @()
    foreach ($directory in @($ConfigDir, $StyleDir)) {
        if (Test-Path -LiteralPath $directory -PathType Container) {
            $candidateFiles += Get-ChildItem -LiteralPath $directory -File -Recurse | Where-Object {
                $_.Extension -in @(".yaml", ".yml", ".lua", ".tex", ".css", ".docx") -and
                $_}
        }
    }

    $unusedCandidates = @($candidateFiles | Where-Object {
        [System.IO.Path]::GetFullPath($_.FullName) -notin $knownPaths
    } | Sort-Object FullName)

    Write-Host "[Unreferenced candidates]"
    if ($unusedCandidates.Count -eq 0) {
        Write-Host "  None"
    }
    else {
        foreach ($file in $unusedCandidates) {
            Write-Host ("  {0}" -f (Get-ProjectRelativePath -Path $file.FullName))
        }
        Write-Host ""
        Write-Host "These files are not directly referenced by the current book.ps1."
        Write-Host "A defaults YAML may still refer to them indirectly, so review before deleting."
    }
}

function Show-BookHelp {
    Write-Host ""
    Write-Host ("book.ps1 version {0}" -f $BookScriptVersion)
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\\book.ps1 <subcommand> [-ProjectRoot <path>]"
    Write-Host ""
    Write-Host "ProjectRoot:"
    Write-Host "  Omit it to use the parent directory of 77_script."
    Write-Host "  The option is available to every subcommand."
    Write-Host "  Example: .\\77_script\\book.ps1 tree -ProjectRoot .\\00_example"
    Write-Host "  Example: .\\77_script\\book.ps1 all -ProjectRoot .\\00_example"
    Write-Host ""
    Write-Host "Subcommands:"
    Write-Host "  setup   Create work directories and update the master manuscript"
    Write-Host "  check   Check external commands and canonical configuration files"
    Write-Host "  config  Show active configuration files, filters, and unreferenced candidates"
    Write-Host "  help    Show this help"
    Write-Host "  master  Generate 10_manuscript\\99_master.md"
    Write-Host "  tree    Copy missing project files from 70_template"
    Write-Host "  Markdown中の fenced Div（::: pagebreak と :::）はPDF、DOCX、EPUBの改ページへ変換されます。前後は空行で区切ってください。"
    Write-Host "  epub    Generate EPUB"
    Write-Host "  pdf     Generate PDF"
    Write-Host "  docx    Generate DOCX"
    Write-Host "  all     Generate EPUB, PDF, and DOCX"
    Write-Host "  clean   Remove reproducible outputs and temporary work files"
}

function Clear-GeneratedFiles {
    Assert-SafeProjectRoot
    Ensure-Directories

    $generatedFiles = @(
        $MasterFile,
        (Join-Path $PublishDir "$OutputBaseName.epub"),
        (Join-Path $PublishDir "$OutputBaseName.pdf"),
        (Join-Path $PublishDir "$OutputBaseName.docx")
    )

    foreach ($file in $generatedFiles) {
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            Remove-Item -LiteralPath $file -Force
            Write-Info "削除しました: $file"
        }
    }

    # 98_workフォルダ内はREADME.mdを残して削除する
    if (Test-Path -LiteralPath $WorkDir -PathType Container) {
        Get-ChildItem -LiteralPath $WorkDir -Force |
            Where-Object {
                $_.Name -ne "README.md" -and
                $_.FullName -ne $RunningLogFile
            } |
            Remove-Item -Recurse -Force
    }

    Write-Success "生成ファイルを整理しました。"
}

try {
    Assert-SafeProjectRoot
    Start-BookLog

    Write-Info (
        "book.ps1 version {0} を開始しました。サブコマンド: {1} / ProjectRoot: {2}" -f
        $BookScriptVersion,
        $Task,
        $ProjectRoot
    )

    switch ($Task) {
        "setup" {
            Ensure-Directories
            Update-Master
            Write-Success "初期設定が完了しました。"
        }

        "check" {
            Test-Environment
        }

        "config" {
            Show-BookConfiguration
        }

        "help" {
            Show-BookHelp
        }

        "master" {
            Update-Master
        }

        "tree" {
            Initialize-ProjectFromTemplate
        }

        "epub" {
            Invoke-PandocExport -Format "epub"
        }

        "pdf" {
            Invoke-PandocExport -Format "pdf"
        }

        "docx" {
            Invoke-PandocExport -Format "docx"
        }

        "all" {
            Update-Master
            Assert-ExportPrerequisites -Formats @("epub", "pdf", "docx") -InputFile $MasterFile
            Write-Info "allの事前検査が完了しました。3形式の生成を開始します。"
            Invoke-PandocExport -Format "epub" -SkipMasterUpdate -SkipPreflight
            Invoke-PandocExport -Format "pdf" -SkipMasterUpdate -SkipPreflight
            Invoke-PandocExport -Format "docx" -SkipMasterUpdate -SkipPreflight
            Write-Success "すべての形式を生成しました。"
        }

        "clean" {
            Clear-GeneratedFiles
        }
    }

    Write-Success "処理が正常に終了しました。"
    Complete-BookLog -Status "success"
}
catch {
    Write-Host ""
    Write-Host (
        "{0} [ERROR] {1}" -f
        (Get-LogLineTimestamp),
        $_.Exception.Message
    ) -ForegroundColor Red

    try {
        Complete-BookLog -Status "fail"
    }
    catch {
        Write-Host (
            "{0} [WARN] ログファイルの終了処理に失敗しました: {1}" -f
            (Get-LogLineTimestamp),
            $_.Exception.Message
        ) -ForegroundColor Yellow
    }

    exit 1
}
