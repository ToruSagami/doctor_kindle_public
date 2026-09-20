#requires -Version 7.0

<#
.SYNOPSIS
VERSIONを正本として、book.ps1の版番号を更新し、
release-manifest.jsonを生成します。

.DESCRIPTION
リリース時の版番号はVERSIONだけを人間が変更します。

このスクリプトはVERSIONから版番号を読み込み、
77_script/book.ps1内の$BookScriptVersionを自動更新した後、
公開対象ファイルのSHA256などを記録した
release-manifest.jsonを生成します。

このスクリプトでは、commit、push、Git tag作成、
GitHub Release作成は行いません。

.EXAMPLE
.\77_script\new_release_manifest.ps1

.EXAMPLE
.\77_script\new_release_manifest.ps1 `
    -Path C:\Users\user\Documents\doctor_kindle_public
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Path = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptVersion = '1.1.0'
$VersionFileName = 'VERSION'
$ManifestFileName = 'release-manifest.json'

function Write-Step {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host ('[INFO] {0}' -f $Message) -ForegroundColor Cyan
}

function Get-RepositoryRelativePath {
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory)]
        [string]$LiteralPath
    )

    return [System.IO.Path]::GetRelativePath(
        $RepositoryRoot,
        $LiteralPath
    ).Replace('\', '/')
}

function Invoke-GitText {
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $result = & git -C $RepositoryRoot @Arguments 2>$null

    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    return (($result | Out-String).Trim())
}

# ------------------------------------------------------------
# Start
# ------------------------------------------------------------

Write-Step (
    'new_release_manifest.ps1 version {0}' -f $ScriptVersion
)

# ------------------------------------------------------------
# Repository
# ------------------------------------------------------------

$RepositoryRoot = (Resolve-Path -LiteralPath $Path).Path

Write-Step (
    'リポジトリを確認します: {0}' -f $RepositoryRoot
)

$insideWorkTree = Invoke-GitText `
    -RepositoryRoot $RepositoryRoot `
    -Arguments @(
        'rev-parse',
        '--is-inside-work-tree'
    )

if ($insideWorkTree -ne 'true') {
    throw (
        'Gitリポジトリではありません: {0}' -f $RepositoryRoot
    )
}

$actualRoot = Invoke-GitText `
    -RepositoryRoot $RepositoryRoot `
    -Arguments @(
        'rev-parse',
        '--show-toplevel'
    )

if ([string]::IsNullOrWhiteSpace($actualRoot)) {
    throw 'Gitリポジトリのルートを取得できませんでした。'
}

$actualRoot = (
    Resolve-Path -LiteralPath $actualRoot
).Path

if ($actualRoot -ne $RepositoryRoot) {
    throw (
        'リポジトリ直下を-Pathへ指定してください。' +
        'リポジトリ直下: {0}' -f $actualRoot
    )
}

# ------------------------------------------------------------
# VERSION
# ------------------------------------------------------------

$versionPath = Join-Path `
    $RepositoryRoot `
    $VersionFileName

if (-not (
    Test-Path `
        -LiteralPath $versionPath `
        -PathType Leaf
)) {
    throw (
        'VERSIONが見つかりません。' +
        '先にVERSIONへリリースする版番号を記載してください。'
    )
}

$Version = (
    Get-Content `
        -LiteralPath $versionPath `
        -Raw `
        -Encoding UTF8
).Trim()

if ([string]::IsNullOrWhiteSpace($Version)) {
    throw 'VERSIONが空です。'
}

if ($Version -notmatch '^\d+\.\d+(?:\.\d+)?$') {
    throw (
        'VERSIONの形式が不正です: {0}。例: 0.7.10' `
            -f $Version
    )
}

Write-Step (
    'VERSIONを読み込みました: {0}' -f $Version
)

# ------------------------------------------------------------
# Target files
# ------------------------------------------------------------

$TargetRelativePaths = @(
    '77_script/apply_revised_files.ps1'
    '77_script/book.ps1'
    '77_script/pdfcover.ps1'
    '77_script/reset_settings.ps1'
    '77_script/setup_windows.ps1'
    '70_template/50_config/docx.yaml'
    '70_template/50_config/epub.yaml'
    '70_template/50_config/metadata.yaml'
    '70_template/50_config/pdf.yaml'
    '70_template/60_style/br.lua'
    '70_template/60_style/code-plain.lua'
    '70_template/60_style/colophon.lua'
    '70_template/60_style/heading-numbering.lua'
    '70_template/60_style/pagebreak.lua'
    '70_template/60_style/pdf-header.tex'
    '70_template/60_style/table-caption.lua'
    '70_template/60_style/table.lua'
)

$missingFiles = [System.Collections.Generic.List[string]]::new()

foreach ($relativePath in $TargetRelativePaths) {

    $fullPath = Join-Path `
        $RepositoryRoot `
        $relativePath

    if (-not (
        Test-Path `
            -LiteralPath $fullPath `
            -PathType Leaf
    )) {
        $missingFiles.Add($relativePath)
    }
}

if ($missingFiles.Count -gt 0) {

    $missingText = $missingFiles -join [Environment]::NewLine

    throw (
        '対象ファイルが見つかりません。' +
        '配置を確認してください。{0}{1}' `
            -f [Environment]::NewLine, $missingText
    )
}

Write-Step '公開対象ファイルの存在を確認しました。'

# ------------------------------------------------------------
# book.ps1 version
# ------------------------------------------------------------

$bookPath = Join-Path `
    $RepositoryRoot `
    '77_script/book.ps1'

$bookText = Get-Content `
    -LiteralPath $bookPath `
    -Raw `
    -Encoding UTF8

$bookVersionPattern = (
    '(?m)^(?<prefix>\s*\$BookScriptVersion\s*=\s*)' +
    '(?<quote>[''"])' +
    '(?<version>[^''"]+)' +
    '\k<quote>'
)

$bookVersionMatch = [regex]::Match(
    $bookText,
    $bookVersionPattern
)

if (-not $bookVersionMatch.Success) {
    throw (
        'book.ps1から$BookScriptVersionを取得できませんでした。'
    )
}

$oldBookVersion = (
    $bookVersionMatch.Groups['version'].Value
)

if ($oldBookVersion -eq $Version) {

    Write-Step (
        'book.ps1の版番号はすでに一致しています: {0}' `
            -f $Version
    )
}
else {

    Write-Step (
        'book.ps1の版番号を更新します: {0} -> {1}' `
            -f $oldBookVersion, $Version
    )

    $bookText = [regex]::Replace(
        $bookText,
        $bookVersionPattern,
        {
            param($match)

            $prefix = $match.Groups['prefix'].Value
            $quote = $match.Groups['quote'].Value

            return (
                $prefix +
                $quote +
                $Version +
                $quote
            )
        },
        1
    )

    Set-Content `
        -LiteralPath $bookPath `
        -Value $bookText `
        -Encoding utf8NoBOM `
        -NoNewline
}

# ------------------------------------------------------------
# Verify book.ps1 version
# ------------------------------------------------------------

$bookTextAfter = Get-Content `
    -LiteralPath $bookPath `
    -Raw `
    -Encoding UTF8

$bookVersionMatchAfter = [regex]::Match(
    $bookTextAfter,
    $bookVersionPattern
)

if (-not $bookVersionMatchAfter.Success) {
    throw (
        '更新後のbook.ps1から' +
        '$BookScriptVersionを取得できませんでした。'
    )
}

$bookVersionAfter = (
    $bookVersionMatchAfter.Groups['version'].Value
)

if ($bookVersionAfter -ne $Version) {
    throw (
        'book.ps1の版番号更新に失敗しました。' +
        'VERSION: {0} / book.ps1: {1}' `
            -f $Version, $bookVersionAfter
    )
}

Write-Step (
    'VERSIONとbook.ps1の版番号が一致しています: {0}' `
        -f $Version
)

# ------------------------------------------------------------
# Git information
# ------------------------------------------------------------

$headCommit = Invoke-GitText `
    -RepositoryRoot $RepositoryRoot `
    -Arguments @(
        'rev-parse',
        'HEAD'
    )

$branch = Invoke-GitText `
    -RepositoryRoot $RepositoryRoot `
    -Arguments @(
        'branch',
        '--show-current'
    )

$remoteUrl = Invoke-GitText `
    -RepositoryRoot $RepositoryRoot `
    -Arguments @(
        'remote',
        'get-url',
        'origin'
    )

# ------------------------------------------------------------
# Manifest files
# ------------------------------------------------------------

$manifestFiles = [System.Collections.Generic.List[object]]::new()

$filesToRecord = @(
    $TargetRelativePaths
) + @(
    $VersionFileName
)

foreach ($relativePath in $filesToRecord) {

    $fullPath = Join-Path `
        $RepositoryRoot `
        $relativePath

    $fileInfo = Get-Item `
        -LiteralPath $fullPath

    $hash = (
        Get-FileHash `
            -LiteralPath $fullPath `
            -Algorithm SHA256
    ).Hash.ToLowerInvariant()

    $lastCommit = Invoke-GitText `
        -RepositoryRoot $RepositoryRoot `
        -Arguments @(
            'log',
            '-1',
            '--format=%H',
            '--',
            $relativePath
        )

    $lastCommitDate = Invoke-GitText `
        -RepositoryRoot $RepositoryRoot `
        -Arguments @(
            'log',
            '-1',
            '--format=%cI',
            '--',
            $relativePath
        )

    $manifestFiles.Add(
        [ordered]@{
            path = Get-RepositoryRelativePath `
                -RepositoryRoot $RepositoryRoot `
                -LiteralPath $fullPath

            sha256 = $hash

            size_bytes = $fileInfo.Length

            last_commit = if (
                [string]::IsNullOrWhiteSpace($lastCommit)
            ) {
                $null
            }
            else {
                $lastCommit
            }

            last_commit_at = if (
                [string]::IsNullOrWhiteSpace($lastCommitDate)
            ) {
                $null
            }
            else {
                $lastCommitDate
            }
        }
    )
}

# ------------------------------------------------------------
# Manifest
# ------------------------------------------------------------

$manifest = [ordered]@{
    schema_version  = 1
    toolkit_version = $Version
    tag             = 'v{0}' -f $Version

    generated_at = (
        Get-Date
    ).ToUniversalTime().ToString('o')

    git = [ordered]@{
        branch      = $branch
        head_commit = $headCommit
        origin      = $remoteUrl
    }

    files = $manifestFiles

    notes = @(
        'release-manifest.json自身は自己参照になるためfilesへ含めません。'
        'VERSIONを版番号の唯一の正本として扱います。'
        'book.ps1のBookScriptVersionはVERSIONから自動更新されます。'
        'last_commitとlast_commit_atは直近のcommit時点の情報です。'
    )
}

# ------------------------------------------------------------
# Write release-manifest.json
# ------------------------------------------------------------

$manifestPath = Join-Path `
    $RepositoryRoot `
    $ManifestFileName

$manifestJson = $manifest |
    ConvertTo-Json -Depth 8

Set-Content `
    -LiteralPath $manifestPath `
    -Value $manifestJson `
    -Encoding utf8NoBOM

Write-Step (
    'release-manifest.jsonを生成しました: {0}' `
        -f $manifestPath
)

# ------------------------------------------------------------
# Final Git status
# ------------------------------------------------------------

$statusAfter = Invoke-GitText `
    -RepositoryRoot $RepositoryRoot `
    -Arguments @(
        'status',
        '--short'
    )

Write-Host ''
Write-Host '========================================'
Write-Host (' Release preparation: v{0}' -f $Version)
Write-Host '========================================'
Write-Host ''

if ([string]::IsNullOrWhiteSpace($statusAfter)) {

    Write-Host 'Gitの変更はありません。'
}
else {

    Write-Host '現在の変更ファイル'
    Write-Host ''
    Write-Host $statusAfter
}

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

Write-Host ''
Write-Host '確認済み'
Write-Host (
    'VERSION               : {0}' `
        -f $Version
)
Write-Host (
    'book.ps1              : {0}' `
        -f $bookVersionAfter
)
Write-Host (
    'release-manifest.json : {0}' `
        -f $Version
)
Write-Host (
    '予定するGit tag       : v{0}' `
        -f $Version
)

# ------------------------------------------------------------
# Next steps
# ------------------------------------------------------------

Write-Host ''
Write-Host '次の作業'
Write-Host '1. book.ps1とrelease-manifest.jsonの差分を確認する'
Write-Host '2. 必要な動作確認を行う'
Write-Host (
    '3. VERSION、book.ps1、release-manifest.jsonを含む変更をcommitする'
)
Write-Host '4. pushする'
Write-Host (
    '5. タグv{0}を作成してpushする' `
        -f $Version
)
Write-Host (
    '6. GitHub Release v{0}を作成する' `
        -f $Version
)

Write-Host ''
Write-Host 'タグ作成時のコマンド'
Write-Host (
    'git tag -a v{0} -m "Release v{0}"' `
        -f $Version
)
Write-Host (
    'git push origin v{0}' `
        -f $Version
)

Write-Host ''
Write-Host 'GitHub Release作成時のコマンド'
Write-Host (
    'gh release create v{0}' `
        -f $Version
)

Write-Host ''
Write-Step (
    'v{0}のリリース準備が完了しました。' `
        -f $Version
)
