# Kindle出版ツールキット

Markdown原稿からEPUB、PDF、DOCXを生成するためのPowerShellスクリプト、設定ファイル、スタイル、原稿テンプレートをまとめた制作キットの公開リポジトリです。

WindowsとVisual Studio Codeを使い、執筆環境の準備から原稿の結合、各形式への変換、ペーパーバック表紙の生成までを一つのフォルダで管理できます。

# 利用方法

## ツールキットを入手する

Gitを利用できる場合は、次のコマンドでリポジトリを取得してください。

```powershell
git clone https://github.com/ToruSagami/doctor_kindle_public.git
cd doctor_kindle_public
```

Gitで取得すると、公開後の修正や更新を`git pull`で反映できます。

```powershell
git pull
```

Gitを利用しない場合は、次のリンクから最新版のZIPファイルをダウンロードしてください。

[最新版Kindle出版ツールキットダウンロード](https://github.com/ToruSagami/doctor_kindle_public/releases/latest/download/kindle-publishing-toolkit.zip)

ダウンロード後、ZIPファイルを任意のフォルダへ展開して使用します。

## 収録内容

| スクリプト | 主な役割 |
|---|---|
| `book.ps1` | 雛形展開、原稿結合、環境確認、設定確認、EPUB、PDF、DOCX生成、生成物整理 |
| `setup_windows.ps1` | Windows出版環境の導入と確認、WinGet設定の入出力 |
| `reset_settings.ps1` | 現在の設定を退避し、`70_template`から標準設定を復元 |
| `pdfcover.ps1` | KDP表紙テンプレートZIPと電子書籍用表紙からペーパーバック表紙を生成 |
| `apply_revised_files.ps1` | `_revised`付きファイルを正式名へ反映し、元ファイルを退避 |

スクリプトのファイル名は固定しています。配布版と変更履歴はGitタグおよびGitHub Releasesで管理します。

## 基本配置

```text
doctor_kindle_public/
├─ .vscode/
├─ 00_example/
├─ 70_template/
├─ 77_script/
│  ├─ apply_revised_files.ps1
│  ├─ book.ps1
│  ├─ pdfcover.ps1
│  ├─ reset_settings.ps1
│  └─ setup_windows.ps1
├─ LICENSE.md
├─ LICENSE_SCOPE.md
├─ THIRD_PARTY_NOTICES.md
└─ README.md
```

`00_example`は動作確認用の実行例です。`70_template`は新しい出版プロジェクトへ展開する原本です。`77_script`には実行用スクリプトを収録しています。

## PowerShellスクリプトのブロックを解除する

ブラウザからZIPファイルをダウンロードした場合、WindowsによってPowerShellスクリプトの実行がブロックされることがあります。

ZIPを展開したフォルダをPowerShellで開き、次のコマンドを実行してください。

```powershell
Get-ChildItem -Path .\77_script -Filter *.ps1 -File | Unblock-File
```

この操作は`77_script`に収録されたPowerShellスクリプトだけを対象にします。`git clone`でリポジトリを取得した場合、通常はこの操作は必要ありません。ブラウザからZIPファイルをダウンロードして展開した場合に実行してください。

## 初回設定：必要な環境を整える

基本環境はWindowsとPowerShell 7です。生成する形式に応じて、Pandoc、MiKTeX、ImageMagick、Node.js、Mermaid CLIなどを使用します。

現在の導入状態は次のコマンドで確認できます。

```powershell
.\77_script\setup_windows.ps1 check
```

必要なアプリをまとめて導入する場合は、次を実行します。

```powershell
.\77_script\setup_windows.ps1 all
```

## 最初に動作確認をする

まず、実行例の設定と外部コマンドを確認します。

```powershell
.\77_script\book.ps1 check -ProjectRoot .\00_example
```

続いて、EPUB、PDF、DOCXをまとめて生成します。

```powershell
.\77_script\book.ps1 all -ProjectRoot .\00_example
```

生成物は`00_example\90_publish`へ出力されます。作業用ファイルとログは`00_example\98_work`へ出力されます。

## 新しい本を始める

リポジトリと同じ階層に新しいフォルダを作る例です。

```powershell
.\77_script\book.ps1 tree -ProjectRoot ..\my_new_book
```

作成された`50_config\metadata.yaml`へ書名、著者名、発行日などを記入し、`10_manuscript`内の各Markdownファイルへ本文を書きます。

`tree`で作成したプロジェクトには、`70_template`と`77_script`もコピーされます。そのため、プロジェクトフォルダを別の場所へ移動した後も、フォルダ単体で原稿の生成、設定の復元、次の書籍プロジェクト作成を行えます。

作成後は書籍プロジェクトへ移動し、プロジェクト内のスクリプトを実行します。

```powershell
cd ..\my_new_book
.\77_script\book.ps1 all
```

`tree`は既存ファイルを上書きしません。新しい版のスクリプトを使う場合は、内容を確認したうえで`77_script`を明示的に更新してください。

## book.ps1の主なコマンド

| コマンド | 処理内容 |
|---|---|
| `help` | 使用方法を表示 |
| `tree` | 雛形、実行スクリプト、次世代用の雛形を不足分だけ展開 |
| `check` | 外部コマンドと主要設定ファイルを確認 |
| `config` | 使用中の設定とフィルターを表示 |
| `master` | 分割原稿から`99_master.md`を生成 |
| `epub` | EPUBを生成 |
| `pdf` | PDFを生成 |
| `docx` | DOCXを生成 |
| `all` | EPUB、PDF、DOCXをまとめて生成 |
| `clean` | 再生成できる生成物と作業ファイルを整理 |

詳しい説明は次のコマンドで確認できます。

```powershell
.\77_script\book.ps1 help
```

## ペーパーバック表紙を作る

電子書籍用表紙をプロジェクトの`30_cover`へ置きます。対応するファイル名は`cover.png`、`cover.jpg`、`cover.jpeg`です。

KDP表紙計算ツールから取得したZIPは、ダウンロードフォルダ、プロジェクト直下、または`99_archive`へ置きます。まずテストを実行します。

```powershell
.\77_script\pdfcover.ps1 test -ProjectRoot .\00_example
```

`98_work`に作成された確認画像で、表表紙の位置、背表紙、裁ち落とし、文字の安全領域を確認します。問題がなければ出版用ファイルを生成します。

```powershell
.\77_script\pdfcover.ps1 create -ProjectRoot .\00_example
```

出版用の`paperback_cover.png`と`paperback_cover.pdf`は`90_publish`へ出力されます。

KDP表紙テンプレートの判型、用紙、ページ数は、最終的な本文PDFと一致させてください。本文のページ数が変わった場合は、KDP表紙計算ツールからテンプレートを取り直します。

## 設定を標準状態へ戻す

現在の`50_config`と`60_style`を`99_archive`へ退避し、`70_template`から標準設定を復元します。

```powershell
.\77_script\reset_settings.ps1 -ProjectRoot .\00_example
```

## 改訂ファイルを反映する

最初に`WhatIf`で変更予定を確認します。

```powershell
.\77_script\apply_revised_files.ps1 .\00_example\10_manuscript -WhatIf
```

確認後、`WhatIf`を外して実行します。サブフォルダも対象にする場合は`Recurse`を指定します。

## 生成物とGit管理

`99_master.md`、`90_publish`の出版用ファイル、`98_work`の中間ファイルとログなどは再生成できるため、原則としてGitの追跡対象外です。

利用者がこのリポジトリから新しい本を始めた後の原稿管理、バックアップ、公開範囲は、各自の方針に合わせて設定してください。書籍原稿や秘密情報を公開リポジトリへ誤って追加しないよう注意が必要です。

## 版の確認

最新版の配布ZIPと変更履歴は、GitHubのReleasesページで確認してください。スクリプト内部の版は、各スクリプトの実行時またはヘルプ表示でも確認できます。

## ライセンス

ライセンスの本文は`LICENSE.md`、適用範囲は`LICENSE_SCOPE.md`、第三者の著作物とライセンス情報は`THIRD_PARTY_NOTICES.md`を確認してください。
