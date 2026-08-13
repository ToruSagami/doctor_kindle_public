# Kindle出版スクリプト統合改訂版

作成日: 2026-08-13

## 収録スクリプト

| スクリプト | バージョン | 主な役割 |
|---|---:|---|
| book_0.6.1.ps1 | 0.6.1 | 雛形展開、原稿結合、環境確認、EPUB・PDF・DOCX生成、生成物整理 |
| setup_windows_0.3.0.ps1 | 0.3.0 | Windows出版環境の導入、確認、WinGet入出力 |
| reset_settings_0.2.0.ps1 | 0.2.0 | 設定を退避し、最新bookと70_templateから復元 |
| pdfcover_0.2.0.ps1 | 0.2.0 | KDPテンプレートZIPと電子書籍表紙からペーパーバック表紙を生成 |
| apply_revised_files_0.2.0.ps1 | 0.2.0 | 改訂版ファイルを正式名へ昇格し、旧版を退避 |

## 基本配置

```text
公開リポジトリ/
├─ 70_template/
└─ 77_script/
   ├─ book_0.6.1.ps1
   ├─ setup_windows_0.3.0.ps1
   ├─ reset_settings_0.2.0.ps1
   ├─ pdfcover_0.2.0.ps1
   └─ apply_revised_files_0.2.0.ps1
```

## 主な実行例

```powershell
.\77_script\setup_windows_0.3.1.ps1 
```

```powershell
.\77_script\book_0.6.1.ps1 tree -ProjectRoot .\00_example
.\77_script\book_0.6.1.ps1 all -ProjectRoot .\00_example
.\77_script\reset_settings_0.2.0.ps1 -ProjectRoot .\00_example
.\77_script\pdfcover_0.2.0.ps1 test -ProjectRoot .\00_example
.\77_script\apply_revised_files_0.2.0.ps1 .\10_manuscript -WhatIf
```

実環境でのPandoc、MiKTeX、WinGet、ImageMagickを使った動的テストは、Windows側の各コマンドが必要です。
