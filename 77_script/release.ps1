#requires -Version 7.0

<#
.SYNOPSIS
VERSIONを基準としてGit commit、push、tag作成、
GitHub Release作成までを実行します。

.DESCRIPTION
new_release_manifest.ps1によるリリース準備が完了した後に実行します。

VERSIONを唯一の版番号の正本として扱い、
以下の処理を順番に実行します。

1. VERSIONを読み込む
2. book.ps1の版番号との一致を確認する
3. release-manifest.jsonの版番号との一致を確認する
4. Gitの変更状態を確認する
5. 変更をcommitする
6. 現在のbranchをpushする
7. VERSIONからGit tagを作成する
8. tagをpushする
9. GitHub Releaseを作成する

既存のtagまたはGitHub Releaseが存在する場合は停止します。

.EXAMPLE
.\77_script\release.ps1

.EXAMPLE
.\77_script\release.ps1 `
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

$ScriptVersion = '1.0.0'
$VersionFileName = 'VERSION'
$ManifestFileName = 'release-manifest.json'

function Write-Step {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host ('[INFO] {0}' -f $Message) -ForegroundColor Cyan
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

function Invoke-GitRequired {
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$ErrorMessage
    )

    & git -C $RepositoryRoot @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw $ErrorMessage
    }
}

# ------------------------------------------------------------
# Start
# ------------------------------------------------------------

Write-Step (
    'release.ps1 version {0}' -f $ScriptVersion
)

# ------------------------------------------------------------
# Repository
# ------------------------------------------------------------

$RepositoryRoot = (
    Resolve-Path -LiteralPath $Path
).Path

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
        'Gitリポジトリではありません: {0}' `
            -f $RepositoryRoot
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
        'リポジトリ直下: {0}' `
            -f $actualRoot
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
    throw 'VERSIONが見つかりません。'
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
        'VERSIONの形式が不正です: {0}' `
            -f $Version
    )
}

$Tag = 'v{0}' -f $Version

Write-Step (
    'リリース対象: {0}' -f $Tag
)

# ------------------------------------------------------------
# Branch
# ------------------------------------------------------------

$branch = Invoke-GitText `
    -RepositoryRoot $RepositoryRoot `
    -Arguments @(
        'branch',
        '--show-current'
    )

if ([string]::IsNullOrWhiteSpace($branch)) {
    throw (
        '現在のbranchを取得できません。' +
        'detached HEADではreleaseできません。'
    )
}

Write-Step (
    '現在のbranch: {0}' -f $branch
)

# ------------------------------------------------------------
# book.ps1 version
# ------------------------------------------------------------

$bookPath = Join-Path `
    $RepositoryRoot `
    '77_script/book.ps1'

if (-not (
    Test-Path `
        -LiteralPath $bookPath `
        -PathType Leaf
)) {
    throw '77_script/book.ps1が見つかりません。'
}

$bookText = Get-Content `
    -LiteralPath $bookPath `
    -Raw `
    -Encoding UTF8

$bookVersionPattern = (
    '(?m)^\s*\$BookScriptVersion\s*=\s*' +
    '[''"](?<version>[^''"]+)[''"]'
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

$bookVersion = (
    $bookVersionMatch.Groups['version'].Value
)

if ($bookVersion -ne $Version) {
    throw (
        'VERSIONとbook.ps1の版番号が一致しません。' +
        'VERSION: {0} / book.ps1: {1}' `
            -f $Version, $bookVersion
    )
}

Write-Step (
    'book.ps1: {0}' -f $bookVersion
)

# ------------------------------------------------------------
# release-manifest.json
# ------------------------------------------------------------

$manifestPath = Join-Path `
    $RepositoryRoot `
    $ManifestFileName

if (-not (
    Test-Path `
        -LiteralPath $manifestPath `
        -PathType Leaf
)) {
    throw (
        'release-manifest.jsonが見つかりません。' +
        '先にnew_release_manifest.ps1を実行してください。'
    )
}

try {
    $manifest = Get-Content `
        -LiteralPath $manifestPath `
        -Raw `
        -Encoding UTF8 |
        ConvertFrom-Json
}
catch {
    throw (
        'release-manifest.jsonを読み込めませんでした。' +
        'JSONの内容を確認してください。'
    )
}

if ($manifest.toolkit_version -ne $Version) {
    throw (
        'VERSIONとrelease-manifest.jsonの版番号が一致しません。' +
        'VERSION: {0} / manifest: {1}' `
            -f $Version, $manifest.toolkit_version
    )
}

if ($manifest.tag -ne $Tag) {
    throw (
        'release-manifest.jsonのtagが一致しません。' +
        '予定: {0} / manifest: {1}' `
            -f $Tag, $manifest.tag
    )
}

Write-Step (
    'release-manifest.json: {0}' `
        -f $manifest.toolkit_version
)

# ------------------------------------------------------------
# Required commands
# ------------------------------------------------------------

$gitCommand = Get-Command `
    git `
    -ErrorAction SilentlyContinue

if ($null -eq $gitCommand) {
    throw 'gitコマンドが見つかりません。'
}

$ghCommand = Get-Command `
    gh `
    -ErrorAction SilentlyContinue

if ($null -eq $ghCommand) {
    throw (
        'ghコマンドが見つかりません。' +
        'GitHub CLIを確認してください。'
    )
}

# ------------------------------------------------------------
# GitHub CLI authentication
# ------------------------------------------------------------

Write-Step 'GitHub CLIの認証状態を確認します。'

& gh auth status *> $null

if ($LASTEXITCODE -ne 0) {
    throw (
        'GitHub CLIへログインしていません。' +
        'gh auth loginを実行してください。'
    )
}

# ------------------------------------------------------------
# Remote
# ------------------------------------------------------------

$remoteUrl = Invoke-GitText `
    -RepositoryRoot $RepositoryRoot `
    -Arguments @(
        'remote',
        'get-url',
        'origin'
    )

if ([string]::IsNullOrWhiteSpace($remoteUrl)) {
    throw 'originが設定されていません。'
}

Write-Step (
    'origin: {0}' -f $remoteUrl
)

# ------------------------------------------------------------
# Existing local tag
# ------------------------------------------------------------

$existingLocalTag = Invoke-GitText `
    -RepositoryRoot $RepositoryRoot `
    -Arguments @(
        'tag',
        '--list',
        $Tag
    )

if ($existingLocalTag -eq $Tag) {
    throw (
        'ローカルにtag {0} がすでに存在します。' `
            -f $Tag
    )
}

# ------------------------------------------------------------
# Existing remote tag
# ------------------------------------------------------------

$existingRemoteTag = Invoke-GitText `
    -RepositoryRoot $RepositoryRoot `
    -Arguments @(
        'ls-remote',
        '--tags',
        'origin',
        ('refs/tags/{0}' -f $Tag)
    )

if (-not [string]::IsNullOrWhiteSpace($existingRemoteTag)) {
    throw (
        'originにtag {0} がすでに存在します。' `
            -f $Tag
    )
}

# ------------------------------------------------------------
# Existing GitHub Release
# ------------------------------------------------------------

& gh release view $Tag `
    --repo $remoteUrl `
    *> $null

if ($LASTEXITCODE -eq 0) {
    throw (
        'GitHub Release {0} がすでに存在します。' `
            -f $Tag
    )
}

# ------------------------------------------------------------
# Git status
# ------------------------------------------------------------

$status = Invoke-GitText `
    -RepositoryRoot $RepositoryRoot `
    -Arguments @(
        'status',
        '--short'
    )

Write-Host ''
Write-Host '========================================'
Write-Host (' Release: {0}' -f $Tag)
Write-Host '========================================'
Write-Host ''

Write-Host ('Repository : {0}' -f $RepositoryRoot)
Write-Host ('Branch     : {0}' -f $branch)
Write-Host ('Version    : {0}' -f $Version)
Write-Host ('Tag        : {0}' -f $Tag)

Write-Host ''
Write-Host '現在のGit変更'
Write-Host ''

if ([string]::IsNullOrWhiteSpace($status)) {
    Write-Host '変更はありません。'
}
else {
    Write-Host $status
}

# ------------------------------------------------------------
# Confirmation
# ------------------------------------------------------------

Write-Host ''
Write-Host 'これから以下を実行します。'
Write-Host ''
Write-Host '1. git add -A'
Write-Host (
    '2. git commit -m "Release {0}"' `
        -f $Tag
)
Write-Host (
    '3. git push origin {0}' `
        -f $branch
)
Write-Host (
    '4. git tag -a {0} -m "Release {0}"' `
        -f $Tag
)
Write-Host (
    '5. git push origin {0}' `
        -f $Tag
)
Write-Host (
    '6. gh release create {0}' `
        -f $Tag
)

Write-Host ''

$confirmation = Read-Host `
    'リリースを続行しますか？ yes と入力してください'

if ($confirmation -ne 'yes') {
    Write-Host ''
    Write-Host 'リリースを中止しました。'
    exit 0
}

# ------------------------------------------------------------
# Commit
# ------------------------------------------------------------

$statusBeforeCommit = Invoke-GitText `
    -RepositoryRoot $RepositoryRoot `
    -Arguments @(
        'status',
        '--porcelain'
    )

if (-not [string]::IsNullOrWhiteSpace($statusBeforeCommit)) {

    Write-Step '変更をstageします。'

    Invoke-GitRequired `
        -RepositoryRoot $RepositoryRoot `
        -Arguments @(
            'add',
            '-A'
        ) `
        -ErrorMessage 'git addに失敗しました。'

    Write-Step (
        'Release {0} をcommitします。' `
            -f $Tag
    )

    Invoke-GitRequired `
        -RepositoryRoot $RepositoryRoot `
        -Arguments @(
            'commit',
            '-m',
            ('Release {0}' -f $Tag)
        ) `
        -ErrorMessage 'git commitに失敗しました。'
}
else {
    Write-Step (
        '未commitの変更がないため、新しいcommitは作成しません。'
    )
}

# ------------------------------------------------------------
# Push branch
# ------------------------------------------------------------

Write-Step (
    'branch {0} をoriginへpushします。' `
        -f $branch
)

Invoke-GitRequired `
    -RepositoryRoot $RepositoryRoot `
    -Arguments @(
        'push',
        'origin',
        $branch
    ) `
    -ErrorMessage 'branchのpushに失敗しました。'

# ------------------------------------------------------------
# Verify clean worktree
# ------------------------------------------------------------

$statusAfterPush = Invoke-GitText `
    -RepositoryRoot $RepositoryRoot `
    -Arguments @(
        'status',
        '--porcelain'
    )

if (-not [string]::IsNullOrWhiteSpace($statusAfterPush)) {
    throw (
        'push後も未commitの変更が残っています。' +
        'tag作成を中止します。'
    )
}

# ------------------------------------------------------------
# Create tag
# ------------------------------------------------------------

Write-Step (
    'tag {0} を作成します。' -f $Tag
)

Invoke-GitRequired `
    -RepositoryRoot $RepositoryRoot `
    -Arguments @(
        'tag',
        '-a',
        $Tag,
        '-m',
        ('Release {0}' -f $Tag)
    ) `
    -ErrorMessage 'Git tagの作成に失敗しました。'

# ------------------------------------------------------------
# Push tag
# ------------------------------------------------------------

Write-Step (
    'tag {0} をoriginへpushします。' `
        -f $Tag
)

Invoke-GitRequired `
    -RepositoryRoot $RepositoryRoot `
    -Arguments @(
        'push',
        'origin',
        $Tag
    ) `
    -ErrorMessage 'Git tagのpushに失敗しました。'

# ------------------------------------------------------------
# GitHub Release
# ------------------------------------------------------------

Write-Step (
    'GitHub Release {0} を作成します。' `
        -f $Tag
)

Push-Location $RepositoryRoot

try {
    & gh release create $Tag `
        --title $Tag `
        --generate-notes

    if ($LASTEXITCODE -ne 0) {
        throw (
            'GitHub Releaseの作成に失敗しました。' +
            'Git tagはすでにoriginへpushされています。'
        )
    }
}
finally {
    Pop-Location
}

# ------------------------------------------------------------
# Result
# ------------------------------------------------------------

$releaseCommit = Invoke-GitText `
    -RepositoryRoot $RepositoryRoot `
    -Arguments @(
        'rev-parse',
        'HEAD'
    )

Write-Host ''
Write-Host '========================================'
Write-Host ' Release completed'
Write-Host '========================================'
Write-Host ''

Write-Host ('Version : {0}' -f $Version)
Write-Host ('Tag     : {0}' -f $Tag)
Write-Host ('Branch  : {0}' -f $branch)
Write-Host ('Commit  : {0}' -f $releaseCommit)

Write-Host ''

Write-Step (
    '{0} のGitHub Release作成まで完了しました。' `
        -f $Tag
)
