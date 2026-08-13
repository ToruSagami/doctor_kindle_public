# Copyright 2026 Toru Sagami
# SPDX-License-Identifier: MIT

<#
.SYNOPSIS
    改訂版ファイルを正式ファイルへ反映し、元ファイルを退避します。
.DESCRIPTION
    filename.extをfilename_old.extへ変更し、
    filename_revised.extをfilename.extへ変更します。
.VERSION
    0.2.1
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$Path,

    [switch]$Recurse
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptVersion = "0.2.1"
$ScriptName = "apply_revised_files"
$rootPath = (Resolve-Path -LiteralPath $Path).Path
$fileSystemRoot = [System.IO.Path]::GetPathRoot($rootPath)

if ([string]::Equals(
        $rootPath.TrimEnd([char[]]@("\", "/")),
        $fileSystemRoot.TrimEnd([char[]]@("\", "/")),
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw "ファイルシステムのルートは対象に指定できません: $rootPath"
}

$searchParams = @{
    LiteralPath = $rootPath
    File        = $true
}

Write-Host ("{0} version {1}" -f $ScriptName, $ScriptVersion)
Write-Host ("対象フォルダ: {0}" -f $rootPath)

if ($Recurse) {
    $searchParams.Recurse = $true
}

$suffix = "_revised"
$revisedFiles = Get-ChildItem @searchParams |
    Where-Object {
        $_.BaseName.EndsWith(
            $suffix,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    }

if (-not $revisedFiles) {
    Write-Host "対象となる改訂版ファイルはありません。"
    return
}

$pairs = foreach ($revisedFile in $revisedFiles) {
    $baseName = $revisedFile.BaseName.Substring(
        0,
        $revisedFile.BaseName.Length - $suffix.Length
    )

    $originalName = $baseName + $revisedFile.Extension
    $oldName = $baseName + "_old" + $revisedFile.Extension

    [pscustomobject]@{
        RevisedPath  = $revisedFile.FullName
        OriginalPath = Join-Path $revisedFile.DirectoryName $originalName
        OldPath      = Join-Path $revisedFile.DirectoryName $oldName
        RevisedName  = $revisedFile.Name
        OriginalName = $originalName
        OldName      = $oldName
    }
}

# 一部だけ名前が変わる事態を避けるため、変更前に全件を検査する。
$problems = foreach ($pair in $pairs) {
    if (-not (Test-Path -LiteralPath $pair.OriginalPath -PathType Leaf)) {
        "対応する元ファイルがありません: $($pair.OriginalPath)"
    }

    if (Test-Path -LiteralPath $pair.OldPath) {
        "退避先がすでに存在します: $($pair.OldPath)"
    }
}

if ($problems) {
    $message = "事前検査で問題が見つかったため、変更していません。`n" +
        ($problems -join "`n")
    throw $message
}

foreach ($pair in $pairs) {
    $descriptionArgs = @(
        $pair.OriginalName,
        $pair.OldName,
        $pair.RevisedName
    )
    $description = "{0}を{1}へ退避し、{2}を{0}へ変更" -f $descriptionArgs

    if ($PSCmdlet.ShouldProcess($pair.OriginalPath, $description)) {
        Rename-Item -LiteralPath $pair.OriginalPath -NewName $pair.OldName

        try {
            Rename-Item -LiteralPath $pair.RevisedPath -NewName $pair.OriginalName
        }
        catch {
            # 改訂版の変更に失敗した場合は、この組の元ファイルを戻す。
            if (
                (Test-Path -LiteralPath $pair.OldPath -PathType Leaf) -and
                -not (Test-Path -LiteralPath $pair.OriginalPath)
            ) {
                Rename-Item -LiteralPath $pair.OldPath -NewName $pair.OriginalName
            }

            throw
        }

        $completedArgs = @(
            $pair.OriginalName,
            $pair.OldName,
            $pair.RevisedName
        )
        Write-Host ("完了: {0} -> {1}, {2} -> {0}" -f $completedArgs)
    }
}
