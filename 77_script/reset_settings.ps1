# Copyright 2026 Toru Sagami
# SPDX-License-Identifier: MIT

<#
.SYNOPSIS
    Kindle出版プロジェクトの設定ファイルを退避し、70_templateから標準設定を復元します。
.VERSION
    0.3.0
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ProjectRoot,

    [switch]$SkipRegenerate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptVersion = "0.3.0"
$ScriptName = "reset_settings"
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

$ConfigDir = Join-Path $ProjectRoot "50_config"
$StyleDir = Join-Path $ProjectRoot "60_style"
$ArchiveRoot = Join-Path $ProjectRoot "99_archive"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupDir = Join-Path $ArchiveRoot ("settings-backup-{0}" -f $Timestamp)

$Targets = @(
    @{
        Directory = $ConfigDir
        Patterns = @("*.yaml", "*.yml")
        BackupSubdirectory = "50_config"
    },
    @{
        Directory = $StyleDir
        Patterns = @("*.tex", "*.lua")
        BackupSubdirectory = "60_style"
    }
)

function Write-Info {
    param([string]$Message)
    Write-Host ("[INFO] {0}" -f $Message) -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host ("[OK]   {0}" -f $Message) -ForegroundColor Green
}

function Write-WarningMessage {
    param([string]$Message)
    Write-Host ("[WARN] {0}" -f $Message) -ForegroundColor Yellow
}

function Assert-SafeProjectRoot {
    $fullProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
    $fileSystemRoot = [System.IO.Path]::GetPathRoot($fullProjectRoot)

    if ([string]::Equals(
            $fullProjectRoot.TrimEnd([char[]]@("\", "/")),
            $fileSystemRoot.TrimEnd([char[]]@("\", "/")),
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw "ファイルシステムのルートはProjectRootに指定できません: $fullProjectRoot"
    }

    $templatePrefix = $TemplateDir.TrimEnd([char[]]@("\", "/")) +
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

function Get-BookScript {
    $bookScriptPath = Join-Path $ScriptDir "book.ps1"

    if (-not (Test-Path -LiteralPath $bookScriptPath -PathType Leaf)) {
        throw "設定復元に必要なbook.ps1が見つかりません: $bookScriptPath"
    }

    return Get-Item -LiteralPath $bookScriptPath
}

function Get-SettingsFiles {
    $files = foreach ($target in $Targets) {
        $directory = [string]$target.Directory

        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            continue
        }

        foreach ($pattern in $target.Patterns) {
            Get-ChildItem -LiteralPath $directory -Filter $pattern -File -Force
        }
    }

    return @($files | Sort-Object FullName -Unique)
}

function Move-SettingsToArchive {
    param([Parameter(Mandatory)][System.IO.FileInfo[]]$Files)

    foreach ($target in $Targets) {
        $sourceDirectory = [string]$target.Directory
        $targetFiles = @(
            $Files | Where-Object { $_.DirectoryName -eq $sourceDirectory }
        )

        if ($targetFiles.Count -eq 0) {
            continue
        }

        $destinationDirectory = Join-Path $BackupDir ([string]$target.BackupSubdirectory)
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null

        foreach ($file in $targetFiles) {
            $destination = Join-Path $destinationDirectory $file.Name
            Move-Item -LiteralPath $file.FullName -Destination $destination
            Write-Info ("退避しました: {0}" -f $file.FullName)
        }
    }
}

try {
    Assert-SafeProjectRoot
    Write-Info ("{0} version {1}" -f $ScriptName, $ScriptVersion)
    Write-Info ("対象プロジェクト: {0}" -f $ProjectRoot)

    $files = Get-SettingsFiles

    if ($files.Count -eq 0) {
        Write-WarningMessage "退避対象のYAML、TEX、Luaファイルはありません。"
    }
    else {
        Write-Info "次の設定ファイルを退避します。"
        foreach ($file in $files) {
            Write-Host ("       {0}" -f $file.FullName)
        }

        Move-SettingsToArchive -Files $files
        Write-Success ("既存設定を退避しました: {0}" -f $BackupDir)
    }

    if ($SkipRegenerate) {
        Write-Success "設定ファイルの退避のみ完了しました。"
        exit 0
    }

    $bookScript = Get-BookScript
    Write-Info ("設定復元に使用します: {0}" -f $bookScript.Name)

    $global:LASTEXITCODE = 0
    & $bookScript.FullName tree -ProjectRoot $ProjectRoot

    if ($LASTEXITCODE -ne 0) {
        throw (
            "{0} treeに失敗しました。終了コード: {1}" -f
            $bookScript.Name,
            $LASTEXITCODE
        )
    }

    Write-Success "70_templateから標準設定を復元しました。"
    Write-Host ""
    Write-Host "確認コマンド:" -ForegroundColor Cyan
    Write-Host (
        '  .\{0} check -ProjectRoot "{1}"' -f
        $bookScript.Name,
        $ProjectRoot
    )
}
catch {
    Write-Host ""
    Write-Host ("[ERROR] {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}
