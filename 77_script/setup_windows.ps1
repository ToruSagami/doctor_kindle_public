# Copyright 2026 Toru Sagami
# SPDX-License-Identifier: MIT
# setup_windows.ps1
# Windows用 Kindle出版環境セットアップ
# Version: 0.3.1

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("prepare", "core", "pdf", "image", "mermaid", "preview", "all", "import", "check", "export", "help", "clean")]
    [string]$Task = "help"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptVersion = "0.3.2"
$ScriptDir = $PSScriptRoot
$ProjectRoot = Split-Path -Parent $ScriptDir
$ScriptFileName = Split-Path -Leaf $PSCommandPath
$WorkDir = Join-Path $ProjectRoot "98_work"
$PackageFile = Join-Path $WorkDir "winget-install.json"
$ExportFile = Join-Path $WorkDir "winget-export.json"
$MermaidPackageName = "@mermaid-js/mermaid-cli"

$LogTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogBaseName = "setup_windows_{0}" -f $Task
$RunningLogFile = Join-Path $WorkDir (
    "{0}_running_{1}.log" -f $LogBaseName, $LogTimestamp
)
$script:TranscriptStarted = $false

$CorePackages = @(
    @{
        Id = "Git.Git"
        Name = "Git"
        Command = "git"
    },
    @{
        Id = "Microsoft.VisualStudioCode"
        Name = "Visual Studio Code"
        Command = "code"
    },
    @{
        Id = "JohnMacFarlane.Pandoc"
        Name = "Pandoc"
        Command = "pandoc"
    }
)

$PdfPackages = @(
    @{
        Id = "MiKTeX.MiKTeX"
        Name = "MiKTeX"
        Command = "lualatex"
    }
)

$ImagePackages = @(
    @{
        Id = "ImageMagick.ImageMagick"
        Name = "ImageMagick"
        Command = "magick"
    }
)

$MermaidPackages = @(
    @{
        Id = "OpenJS.NodeJS.LTS"
        Name = "Node.js LTS"
        Command = "node"
    }
)

$PreviewPackages = @(
    @{
        Id = "Amazon.KindlePreviewer"
        Name = "Kindle Previewer"
        Command = $null
    }
)

$AllWingetPackages = $CorePackages + $PdfPackages + $ImagePackages + $MermaidPackages + $PreviewPackages

function Start-SetupLog {
    if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) {
        New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    }

    Start-Transcript -LiteralPath $RunningLogFile -Force | Out-Null
    $script:TranscriptStarted = $true
}

function Complete-SetupLog {
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

function Get-LogLineTimestamp {
    return Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

function Write-Info {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ("{0} [INFO] {1}" -f (Get-LogLineTimestamp), $Message) -ForegroundColor Cyan
}

function Write-Success {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ("{0} [OK]   {1}" -f (Get-LogLineTimestamp), $Message) -ForegroundColor Green
}

function Write-WarningMessage {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ("{0} [WARN] {1}" -f (Get-LogLineTimestamp), $Message) -ForegroundColor Yellow
}

function Write-Utf8WithoutBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText(
        $Path,
        $Content.Trim() + [Environment]::NewLine,
        $utf8WithoutBom
    )
}

function Show-Help {
    Write-Host ""
    Write-Host ("{0} version {1}" -f $ScriptFileName, $ScriptVersion) -ForegroundColor Green
    Write-Host ""
    Write-Host "Usage:"
    Write-Host ("  .\{0} <task>" -f $ScriptFileName)
    Write-Host ""
    Write-Host "Tasks:"
    Write-Host "  prepare  98_workにWinGetインポート用JSONを生成"
    Write-Host "  core     Git、Visual Studio Code、Pandocを導入"
    Write-Host "  pdf      MiKTeXを導入"
    Write-Host "  image    ImageMagickを導入"
    Write-Host "  mermaid  Node.js LTSとMermaid CLIを導入"
    Write-Host "  preview  Kindle Previewerを導入"
    Write-Host "  all      上記すべてを導入し、Mermaid CLIの導入も試行"
    Write-Host "  import   WinGet設定JSONからアプリを導入し、Mermaid CLIの導入も試行"
    Write-Host "  check    必要なアプリとコマンドを確認"
    Write-Host "  export   WinGet管理アプリ一覧をJSONへ出力"
    Write-Host "  help     このヘルプを表示"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host ("  .\{0} prepare" -f $ScriptFileName)
    Write-Host ("  .\{0} all" -f $ScriptFileName)
    Write-Host ("  .\{0} check" -f $ScriptFileName)
    Write-Host ""
    Write-Host "Note:"
    Write-Host "  Mermaid CLIはnpmパッケージです。"
    Write-Host "  インストール後はmmdcコマンドとして実行します。"
    Write-Host ""
}

function New-WinGetImportJson {
    $packages = @(
        $AllWingetPackages | ForEach-Object {
            [ordered]@{ PackageIdentifier = $_.Id }
        }
    )

    $manifest = [ordered]@{
        '$schema' = "https://aka.ms/winget-packages.schema.2.0.json"
        CreationDate = (Get-Date).ToUniversalTime().ToString("o")
        Sources = @(
            [ordered]@{
                Packages = $packages
                SourceDetails = [ordered]@{
                    Argument = "https://cdn.winget.microsoft.com/cache"
                    Identifier = "Microsoft.Winget.Source_8wekyb3d8bbwe"
                    Name = "winget"
                    Type = "Microsoft.PreIndexed.Package"
                }
            }
        )
    }

    return ($manifest | ConvertTo-Json -Depth 8)
}

function Initialize-ConfigFiles {
    if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) {
        New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
        Write-Info ("作業フォルダを作成しました: {0}" -f $WorkDir)
    }

    $packageJson = New-WinGetImportJson
    Write-Utf8WithoutBom -Path $PackageFile -Content $packageJson
    Write-Success ("WinGetインポート用JSONを更新しました: {0}" -f $PackageFile)
}

function Assert-WinGet {
    $wingetCommand = Get-Command "winget" -ErrorAction SilentlyContinue

    if ($null -eq $wingetCommand) {
        throw @"
wingetが見つかりません。

Microsoft Storeの「アプリ インストーラー」を更新した後、
PowerShellを開き直して再実行してください。
"@
    }

    Write-Success ("wingetを確認しました: {0}" -f $wingetCommand.Source)
    & winget --version
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")

    $segments = New-Object System.Collections.Generic.List[string]

    foreach ($pathValue in @($machinePath, $userPath)) {
        if ([string]::IsNullOrWhiteSpace($pathValue)) {
            continue
        }

        foreach ($segment in ($pathValue -split ";")) {
            if ([string]::IsNullOrWhiteSpace($segment)) {
                continue
            }

            if (-not $segments.Contains($segment)) {
                $segments.Add($segment)
            }
        }
    }

    $npmGlobalDirectory = Join-Path $env:APPDATA "npm"
    if (-not $segments.Contains($npmGlobalDirectory)) {
        $segments.Add($npmGlobalDirectory)
    }

    $env:Path = $segments -join ";"
    Write-Info "現在のPowerShellプロセスへ最新のPATHを再読み込みしました。"
}

function Find-CommandPath {
    param(
        [Parameter(Mandatory = $true)][string]$CommandName,
        [string[]]$FallbackPaths = @()
    )

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    Refresh-ProcessPath

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    foreach ($fallbackPath in $FallbackPaths) {
        if (-not [string]::IsNullOrWhiteSpace($fallbackPath) -and
            (Test-Path -LiteralPath $fallbackPath -PathType Leaf)) {
            return $fallbackPath
        }
    }

    return $null
}

function Test-PackageAvailable {
    param([Parameter(Mandatory = $true)][string]$PackageId)

    & winget show `
        --id $PackageId `
        --exact `
        --source winget `
        --accept-source-agreements `
        --disable-interactivity | Out-Null

    return ($LASTEXITCODE -eq 0)
}

function Test-PackageInstalled {
    param([Parameter(Mandatory = $true)][string]$PackageId)

    & winget list `
        --id $PackageId `
        --exact `
        --accept-source-agreements `
        --disable-interactivity | Out-Null

    return ($LASTEXITCODE -eq 0)
}

function Install-Package {
    param([Parameter(Mandatory = $true)][hashtable]$Package)

    $packageId = [string]$Package.Id
    $packageName = [string]$Package.Name

    Write-Info ("{0}を確認しています: {1}" -f $packageName, $packageId)

    if (-not (Test-PackageAvailable -PackageId $packageId)) {
        throw ("WinGetソースにパッケージが見つかりません: {0}" -f $packageId)
    }

    if (Test-PackageInstalled -PackageId $packageId) {
        Write-Success ("{0}は既にインストールされています。" -f $packageName)
        return
    }

    Write-Info ("{0}をインストールしています。" -f $packageName)

    & winget install `
        --id $packageId `
        --exact `
        --source winget `
        --accept-package-agreements `
        --accept-source-agreements `
        --disable-interactivity

    if ($LASTEXITCODE -ne 0) {
        throw ("{0}のインストールに失敗しました。終了コード: {1}" -f $packageName, $LASTEXITCODE)
    }

    Write-Success ("{0}をインストールしました。" -f $packageName)
}

function Install-PackageSet {
    param([Parameter(Mandatory = $true)][array]$Packages)

    foreach ($package in $Packages) {
        Install-Package -Package $package
    }
}

function Install-MermaidCli {
    Write-Info "Mermaid CLIの導入状態を確認しています。"

    $mmdcFallbacks = @(
        (Join-Path $env:APPDATA "npm\mmdc.cmd"),
        (Join-Path $env:APPDATA "npm\mmdc.ps1")
    )

    $mmdcPath = Find-CommandPath -CommandName "mmdc" -FallbackPaths $mmdcFallbacks
    if (-not [string]::IsNullOrWhiteSpace($mmdcPath)) {
        Write-Success ("Mermaid CLIは既に利用できます: {0}" -f $mmdcPath)
        & $mmdcPath --version
        return
    }

    $npmFallbacks = @(
        (Join-Path $env:ProgramFiles "nodejs\npm.cmd"),
        (Join-Path ${env:ProgramFiles(x86)} "nodejs\npm.cmd")
    )

    $npmPath = Find-CommandPath -CommandName "npm.cmd" -FallbackPaths $npmFallbacks
    if ([string]::IsNullOrWhiteSpace($npmPath)) {
        $npmPath = Find-CommandPath -CommandName "npm" -FallbackPaths $npmFallbacks
    }

    if ([string]::IsNullOrWhiteSpace($npmPath)) {
        throw ((@"
Node.jsのインストール後もnpmが見つかりません。

PowerShellまたはVS Codeを閉じて開き直した後、次を実行してください。
  .\{0} mermaid
"@) -f $ScriptFileName)
    }

    Write-Success ("npmを確認しました: {0}" -f $npmPath)
    Write-Info ("Mermaid CLIをグローバルインストールしています: {0}" -f $MermaidPackageName)

    & $npmPath install --global $MermaidPackageName

    if ($LASTEXITCODE -ne 0) {
        throw ("Mermaid CLIのインストールに失敗しました。終了コード: {0}" -f $LASTEXITCODE)
    }

    Refresh-ProcessPath
    $mmdcPath = Find-CommandPath -CommandName "mmdc" -FallbackPaths $mmdcFallbacks

    if ([string]::IsNullOrWhiteSpace($mmdcPath)) {
        throw ((@"
Mermaid CLIのインストールは完了しましたが、現在のPowerShellからmmdcを確認できません。

PowerShellまたはVS Codeを閉じて開き直した後、次を実行してください。
  .\{0} check
"@) -f $ScriptFileName)
    }

    Write-Success ("Mermaid CLIをインストールしました: {0}" -f $mmdcPath)
    & $mmdcPath --version
}

function Test-Commands {
    param(
        [Parameter(Mandatory = $true)][array]$Packages,
        [switch]$IncludeMermaidCommands
    )

    Write-Info "アプリとコマンドの利用可否を確認しています。"

    foreach ($package in $Packages) {
        $commandName = $package.Command
        $displayName = [string]$package.Name
        $packageId = [string]$package.Id

        if ([string]::IsNullOrWhiteSpace([string]$commandName)) {
            if (Test-PackageInstalled -PackageId $packageId) {
                Write-Success ("{0}のインストールを確認しました。" -f $displayName)
            }
            else {
                Write-WarningMessage ("{0}がインストールされていません: {1}" -f $displayName, $packageId)
            }

            continue
        }

        $fallbacks = @()
        switch ([string]$commandName) {
            "node" {
                $fallbacks = @(
                    (Join-Path $env:ProgramFiles "nodejs\node.exe"),
                    (Join-Path ${env:ProgramFiles(x86)} "nodejs\node.exe")
                )
            }
            "lualatex" {
                $fallbacks = @()
            }
        }

        $commandPath = Find-CommandPath -CommandName ([string]$commandName) -FallbackPaths $fallbacks

        if ([string]::IsNullOrWhiteSpace($commandPath)) {
            Write-WarningMessage ("{0}のコマンドが見つかりません: {1}" -f $displayName, $commandName)
        }
        else {
            Write-Success ("{0}を確認しました: {1}" -f $displayName, $commandPath)
        }
    }

    if ($IncludeMermaidCommands) {
        foreach ($extraCommand in @("npm", "mmdc")) {
            $fallbacks = @()

            if ($extraCommand -eq "npm") {
                $fallbacks = @(
                    (Join-Path $env:ProgramFiles "nodejs\npm.cmd"),
                    (Join-Path ${env:ProgramFiles(x86)} "nodejs\npm.cmd")
                )
            }
            elseif ($extraCommand -eq "mmdc") {
                $fallbacks = @(
                    (Join-Path $env:APPDATA "npm\mmdc.cmd"),
                    (Join-Path $env:APPDATA "npm\mmdc.ps1")
                )
            }

            $commandPath = Find-CommandPath -CommandName $extraCommand -FallbackPaths $fallbacks
            if ([string]::IsNullOrWhiteSpace($commandPath)) {
                Write-WarningMessage ("コマンドが見つかりません: {0}" -f $extraCommand)
            }
            else {
                Write-Success ("{0}を確認しました: {1}" -f $extraCommand, $commandPath)
            }
        }
    }

    Write-Info "新規インストール後にコマンドが見つからない場合は、PowerShellまたはVS Codeを開き直してください。"
}

function Import-Packages {
    Initialize-ConfigFiles

    if (-not (Test-Path -LiteralPath $PackageFile -PathType Leaf)) {
        throw ("インポート用JSONが見つかりません: {0}" -f $PackageFile)
    }

    Write-Info ("WinGetパッケージ一覧をインポートします: {0}" -f $PackageFile)

    & winget import `
        --import-file $PackageFile `
        --ignore-versions `
        --no-upgrade `
        --accept-package-agreements `
        --accept-source-agreements `
        --disable-interactivity

    if ($LASTEXITCODE -ne 0) {
        throw ("winget importに失敗しました。終了コード: {0}" -f $LASTEXITCODE)
    }

    Write-Success "WinGetパッケージ一覧のインポートが完了しました。"
}


function Remove-SetupLogs {
    if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) {
        Write-Info ("ログフォルダがないため、削除対象はありません: {0}" -f $WorkDir)
        return
    }

    $logNamePattern = '^setup_windows_(prepare|core|pdf|image|mermaid|preview|all|import|check|export|help|clean)_(running|success|fail)_\d{8}_\d{6}\.log$'
    $logFiles = @(
        Get-ChildItem -LiteralPath $WorkDir -File -ErrorAction Stop |
            Where-Object { $_.Name -match $logNamePattern }
    )

    if ($logFiles.Count -eq 0) {
        Write-Info ("setup_windowsが作成したログは見つかりませんでした: {0}" -f $WorkDir)
        return
    }

    $deletedCount = 0

    foreach ($logFile in $logFiles) {
        Remove-Item -LiteralPath $logFile.FullName -Force -ErrorAction Stop
        $deletedCount++
        Write-Success ("ログを削除しました: {0}" -f $logFile.Name)
    }

    Write-Success ("setup_windowsのログを削除しました。件数: {0}" -f $deletedCount)
}

function Export-Packages {
    if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) {
        New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    }

    Write-Info ("現在のWinGet管理アプリを保存します: {0}" -f $ExportFile)

    & winget export `
        --output $ExportFile `
        --source winget `
        --accept-source-agreements `
        --include-versions

    if ($LASTEXITCODE -ne 0) {
        throw ("winget exportに失敗しました。終了コード: {0}" -f $LASTEXITCODE)
    }

    Write-Success ("インストール済みアプリ一覧を保存しました: {0}" -f $ExportFile)
}


if ($Task -eq "clean") {
    try {
        Remove-SetupLogs
        exit 0
    }
    catch {
        Write-Host ""
        Write-Host (
            "{0} [ERROR] {1}" -f
            (Get-LogLineTimestamp),
            $_.Exception.Message
        ) -ForegroundColor Red
        exit 1
    }
}

try {
    Start-SetupLog

    Write-Info (
        "{0} version {1} を開始しました。サブコマンド: {2}" -f
        $ScriptFileName,
        $ScriptVersion,
        $Task
    )

    switch ($Task) {
        "prepare" {
            Initialize-ConfigFiles
        }

        "core" {
            Assert-WinGet
            Install-PackageSet -Packages $CorePackages
            Test-Commands -Packages $CorePackages
        }

        "pdf" {
            Assert-WinGet
            Install-PackageSet -Packages $PdfPackages
            Test-Commands -Packages $PdfPackages
        }

        "image" {
            Assert-WinGet
            Install-PackageSet -Packages $ImagePackages
            Test-Commands -Packages $ImagePackages
        }

        "mermaid" {
            Assert-WinGet
            Install-PackageSet -Packages $MermaidPackages
            Refresh-ProcessPath
            Install-MermaidCli
            Test-Commands -Packages $MermaidPackages -IncludeMermaidCommands
        }

        "preview" {
            Assert-WinGet
            Install-PackageSet -Packages $PreviewPackages
            Test-Commands -Packages $PreviewPackages
        }

        "all" {
            Assert-WinGet
            Install-PackageSet -Packages $AllWingetPackages
            Refresh-ProcessPath
            Install-MermaidCli
            Test-Commands -Packages $AllWingetPackages -IncludeMermaidCommands
        }

        "import" {
            Assert-WinGet
            Import-Packages
            Refresh-ProcessPath
            Install-MermaidCli
            Test-Commands -Packages $AllWingetPackages -IncludeMermaidCommands
        }

        "check" {
            Assert-WinGet
            Refresh-ProcessPath
            Test-Commands -Packages $AllWingetPackages -IncludeMermaidCommands
        }

        "export" {
            Assert-WinGet
            Export-Packages
        }

        "help" {
            Show-Help
        }
    }

    Write-Success "処理が正常に終了しました。"
    Complete-SetupLog -Status "success"
}
catch {
    Write-Host ""
    Write-Host (
        "{0} [ERROR] {1}" -f
        (Get-LogLineTimestamp),
        $_.Exception.Message
    ) -ForegroundColor Red

    try {
        Complete-SetupLog -Status "fail"
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
