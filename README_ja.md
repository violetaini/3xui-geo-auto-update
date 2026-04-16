# 3xui Geo Updater

[English](README.md) | [简体中文](README_zh.md) | [日本語](README_ja.md) | [Русский](README_ru.md) | [فارسی](README_fa.md)

**3x-ui** 向けの軽量で多言語対応の Geo ファイル自動更新ツールです。ソース選択、定期更新、ログ記録、安全な再起動メカニズムを備えています。

![Main Menu Preview](screenshots/main-menu-preview.png)

このツールは、3x-ui ベースの環境で Geo 関連のルールファイルを最新の状態に保ちつつ、不要な再起動を防ぐのに役立ちます。複数のアップストリームソース、柔軟なスケジューリング、シンプルなコマンドラインメニューをサポートし、**ファイルが実際に変更された場合のみ**再起動を実行します。

## 主な機能

- 多言語インターフェース
  - 簡体字中国語 (Simplified Chinese)
  - 英語 (English)
  - ロシア語 (Russian)
  - ペルシャ語 (Persian)
- 初回起動時の言語選択
- 複数の Geo ルールソースをサポート
- 単一または複数のソース選択をサポート
- 定期更新モード
  - 毎日 (Daily)
  - 毎週 (Weekly)
  - N日ごと (Every N days)
  - カスタム cron 式
- デフォルト実行時間：**03:00**
- **ファイルが実際に変更された場合のみ x-ui を再起動**
- ログ記録のサポート
- 組み込みのアンインストールオプション
- 組み込みのスワップ (Swap) 管理メニュー
- ショートカットコマンド：
  - `xgeo`
  - `3xui-geo`
- スケジューラーバックエンドの自動選択
  - 標準システムではシステム cron を使用
  - メモリが少ないサポート対象の RHEL 系システムでは、まず利用可能な組み込みのシステム cron が存在するかどうかを確認
  - 利用可能なシステム cron がない場合、インストーラーは自動的に Supercronic に切り替わります
- Supercronic モードの機能：
  - systemd サービス管理
  - 起動時の自動実行
  - 障害時の自動再起動

## サポートされているソース

現在、以下の Geo ルールソースをサポートしています：

1. **Loyalsoldier**
   - `geoip.dat`
   - `geosite.dat`

2. **chocolate4u**
   - `geoip_IR.dat`
   - `geosite_IR.dat`

3. **runetfreedom**
   - `geoip_RU.dat`
   - `geosite_RU.dat`

## サポートされている OS

インストーラーは現在、以下の Linux ファミリー向けに設計およびテストされています：

- Alpine
- Debian
- Kali
- Ubuntu
- Anolis
- RHEL
- AlmaLinux
- Rocky Linux
- Oracle Linux
- Alibaba Cloud Linux
- OpenCloudOS
- CentOS Stream
- Fedora
- openEuler
- Arch Linux

**注意事項：**

- **Debian / Kali / Ubuntu** などの Debian 系システムは `apt + cron` インストールパスに従います
- **Anolis / RHEL / AlmaLinux / Rocky / Oracle / Alibaba Cloud Linux / OpenCloudOS / CentOS Stream / Fedora / openEuler** などの RHEL 系システムは RHEL 系スケジューラーパスに従います
- メモリが少ないサポート対象の RHEL 系システムでは、まず利用可能な組み込みのシステム cron が既に存在するかどうかを確認します
- 利用可能な組み込みのシステム cron が存在する場合、ネイティブのシステム cron がそのまま使用されます
- 存在しない場合、インストーラーは自動的に **Supercronic** に切り替わります

必要なツールと cron 環境がすでに存在する場合、他の Linux ディストリビューションでも機能する可能性がありますが、現在は主要なサポート対象ではありません。

## 動作の仕組み

アップデーターは、設定されたアップストリームソースから最新の Geo ファイルをダウンロードし、現在インストールされているローカルファイルと比較します。ファイルの内容が変更されている場合にのみファイルを置き換えます。

選択したファイルが少なくとも1つ変更された場合、スクリプトは `x-ui` を再起動し、新しい Geo データを適用します。

何も変更がない場合、**再起動は行われません**。

## このプロジェクトが存在する理由

3x-ui にはすでに手動の Geo ファイル更新オプションがありますが、多くのユーザーはより安全で自動化されたワークフローを求めています。

本プロジェクトは以下を追加します：

- スケジュール実行
- ソースの選択
- 多言語インタラクティブ管理
- ログ記録
- 変更時のみ再起動するロジック
- 初回起動時の言語選択
- 長期的なメンテナンスのためのより便利な操作体験

## 動作要件

- Linux サーバー
- `3x-ui` がインストール済みであること
- Root 権限
- 一般的なシステムツールが利用可能であること：
  - `bash`, `curl`, `cmp`, `install`, `awk`, `grep`, `mktemp`, `date`, `xargs`

このインストーラーは、標準的な Linux システムで通常利用可能な一般的な Linux ユーティリティに主に依存しています。

標準システムでは、必要に応じてインストーラーが自動的に cron をインストールして起動しようとします。

メモリが少ないサポート対象の RHEL 系システムでは、まず利用可能な組み込みのシステム cron が既に存在するかどうかを確認します。存在する場合、ネイティブのシステム cron が使用されます。そうでない場合、インストーラーは自動的に **Supercronic** に切り替わります。

## インストール

### クイックインストール
インストーラーはスケジューラーバックエンドを自動的に選択します：
- 標準システムではシステム cron を使用し、必要に応じてインストール/起動を試みます。
- メモリが少ないサポート対象の RHEL 系システムでは、まず利用可能な組み込みのシステム cron が既に存在するかどうかを確認します。
- 利用可能な組み込みのシステム cron がある場合は、それを直接使用します。
- そうでない場合、インストーラーは自動的に **Supercronic** に切り替わります。
```bash
curl -fsSL -o install-3xui-geo-updater.sh [https://raw.githubusercontent.com/violetaini/3xui-geo-auto-update/main/install-3xui-geo-updater.sh](https://raw.githubusercontent.com/violetaini/3xui-geo-auto-update/main/install-3xui-geo-updater.sh) && chmod +x install-3xui-geo-updater.sh && bash install-3xui-geo-updater.sh
```

### 1. インストーラーをダウンロード

インストーラースクリプトをサーバーにダウンロードします：

```bash
curl -fsSL -o install-3xui-geo-updater.sh [https://raw.githubusercontent.com/violetaini/3xui-geo-auto-update/main/install-3xui-geo-updater.sh](https://raw.githubusercontent.com/violetaini/3xui-geo-auto-update/main/install-3xui-geo-updater.sh)
```

または、リポジトリをクローンします：

```bash
git clone [https://github.com/violetaini/3xui-geo-auto-update.git](https://github.com/violetaini/3xui-geo-auto-update.git)
cd 3xui-geo-auto-update
```

### 2. 実行権限を付与

```bash
chmod +x install-3xui-geo-updater.sh
```

### 3. root 権限で実行

```bash
sudo bash install-3xui-geo-updater.sh
```

インストール後、管理メニューが自動的に起動します。

### 初回起動時
初回起動時に、メインメニューに入る前に言語を選択するよう求められます。
その後、選択した言語が保存され、自動的に使用されます。

## 使用方法

**管理メニューを開く：**

```bash
xgeo
```

または

```bash
3xui-geo
```

**手動で更新チェックを実行：**
メニューを開き、「今すぐ更新チェックを実行する」を選択します。

**アンインストール：**

```bash
xgeo uninstall
```

管理メニューからもアンインストール可能です。

## メニューの概要

- 自動更新の設定または変更
- 今すぐ更新チェックを実行
- ログの表示
- 現在の設定の表示
- 言語の切り替え
- スケジュールタスクの削除
- スワップ (Swap) 管理
- スクリプトのアンインストール

## スケジュールモード

本ツールは以下のスケジュールモードをサポートしています：

- **毎日 (Daily)：** 毎日 03:00 に実行
- **毎週 (Weekly)：** 毎週指定した曜日の 03:00 に実行
- **N日ごと (Every N Days)：** N日ごとの 03:00 に実行
- **カスタム Cron：** 完全なスケジュール制御を求める上級ユーザー向け

## スケジューラーバックエンド

本プロジェクトは2つのスケジューラーバックエンドをサポートしています：

### 1. システム cron
標準システムで使用されます。

cron がない場合、インストーラーが自動的にインストールと起動を試みます。

### 2. Supercronic
メモリの少ないサポート対象の RHEL 系システムで、必要な場合にのみ使用されます。

現在、インストーラーは以下のシステムをチェックして、低メモリスケジューラーのフォールバックを実行します：

- Anolis
- RHEL
- AlmaLinux
- Rocky Linux
- Oracle Linux
- OpenCloudOS
- CentOS Stream
- Fedora
- openEuler
- Alibaba Cloud Linux

総メモリが **2 GiB** 未満の場合、インストーラーはまず利用可能な組み込みのシステム cron が既に存在するかどうかを確認します。

- 利用可能な組み込みのシステム cron が見つかった場合、インストーラーはネイティブのシステム cron を使用し続けます。
- 利用可能な組み込みのシステム cron が見つからない場合、インストーラーは自動的に **Supercronic** に切り替わります。

Supercronic モードでは、インストーラーは以下の処理を行います：
- Supercronic のスタンドアロンバイナリをダウンロード
- 専用の crontab ファイルを作成
- systemd サービスを作成
- 起動時の自動実行を有効化
- 障害時の自動再起動を有効化

## ログ記録

デフォルトのログファイル：

```bash
/var/log/3xui-geo-updater.log
```

最後の 50 行を表示：

```bash
tail -n 50 /var/log/3xui-geo-updater.log
```

リアルタイムでログを追跡：

```bash
tail -f /var/log/3xui-geo-updater.log
```

## インストールされるコンポーネント

インストーラーは以下のファイルを作成します：

- `/usr/local/bin/3xui-geo-runner.sh`
- `/usr/local/bin/3xui-geo-manager.sh`
- `/usr/local/bin/3xui-geo-uninstall.sh`
- `/usr/local/bin/xgeo`
- `/usr/local/bin/3xui-geo`

設定ファイル：
- `/etc/3xui-geo-updater.conf`

状態ディレクトリ：
- `/var/lib/3xui-geo-updater`

ログファイル：
- `/var/log/3xui-geo-updater.log`

Supercronic モードが有効な場合、以下のファイルも作成されます：
- `/usr/local/bin/supercronic`
- `/etc/3xui-geo-updater.cron`
- `/etc/systemd/system/3xui-geo-supercronic.service`

## 安全メカニズム

本プロジェクトには、安全性を重視した以下のメカニズムが含まれています：

- 置換前のファイル内容の比較
- 実際のファイル変更時のみの再起動
- 同時実行を防ぐためのプロセスロック
- 実行前の依存関係チェック
- システム環境に基づいたスケジューラーバックエンドの自動選択
- 標準システムでの cron の自動インストールと起動修復
- サポート対象のメモリの少ない RHEL 系システムにおいて、**利用可能な組み込み cron がない場合**の Supercronic への自動フォールバック
- 再設定時のスケジュールタスクの重複排除
- 専用のアンインストールスクリプト
- アンインストール後のシェルキャッシュクリアのリマインダー

## デプロイに関する注意事項

このプロジェクトは、3x-ui がすでにインストールされ、正常に機能しているサーバーを対象としています。
3x-ui 自体はインストールしません。

標準的な Linux システムでは、cron がない場合、自動的にインストールと起動を試みます。

メモリの少ないサポート対象の RHEL 系システムでは、まず利用可能な組み込みのシステム cron が既に存在するかどうかを確認します。

存在する場合、ネイティブのシステム cron が使用されます。

存在しない場合、自動的に Supercronic に切り替わります。

## オープンソースに関する通知と免責事項

このプロジェクトは独立したコミュニティツールです。
以下のいずれとも提携、承認、または公式にサポートされていません：

- 3x-ui
- Xray
- Supercronic
- 上流の Geo ルールメンテナー
- ホスティングプロバイダーまたはサービスオペレーター

### 無保証
このソフトウェアは「現状有姿」で提供され、商品性、特定目的への適合性、非侵害性、可用性、および運用上の安全性を含むがこれらに限定されない、明示または黙示を問わず、いかなる種類の保証もありません。
**ご自身の責任において使用してください。**

### ユーザーの責任
このプロジェクトを使用することにより、お客様は以下に同意するものとします：

- 実行前にコードを確認する責任があります
- お客様の管轄区域でその使用が合法であることを確認する責任があります
- お客様のサーバー、ネットワーク、プロバイダー、およびサービス規約に準拠していることを確認する責任があります
- このツールの使用によって引き起こされた設定変更、ダウンタイム、またはサービスへの影響について責任を負います

### アップストリームデータとサードパーティの権利
本プロジェクトは、サードパーティのアップストリームソースからルールファイルをダウンロードする場合があります。
それらのファイル、命名規則、更新ロジック、および関連するすべての権利は、それぞれのメンテナーまたは所有者に帰属します。
ユーザーは、有効にするアップストリームデータソースのライセンス、利用規約、および使用条件を確認する必要があります。

### セキュリティに関する推奨事項
インターネット上の自動化スクリプトを本番システムで盲目的に実行しないでください。
常にコードを確認し、最初に安全な環境でテストを行い、重要な設定とデータのバックアップを保管してください。

### 法的通知
このリポジトリは、教育、運用、および管理の自動化のみを目的としています。
このリポジトリのいかなる内容も、法的アドバイス、コンプライアンスに関するアドバイス、またはいかなる国や環境での合法的な使用を保証するものと解釈されるべきではありません。

## ライセンス (License)

MIT License

```text
MIT License

Copyright (c) 2026 violetaini

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## リポジトリ構造

```text
.
├── install-3xui-geo-updater.sh
├── LICENSE
├── README.md
├── README_fa.md
├── README_ja.md
├── README_ru.md
├── README_zh.md
└── screenshots/
    └── main-menu-preview.png
```
