<div align="center">

# Board-Man

**macOSのクリップボードを、履歴から作業面へ。**

履歴、定型文、Pin、検索、使用回数、画像プレビューを1つのパネルにまとめたローカルファーストのメニューバーアプリです。

[![Board-Man CI](https://github.com/uniplanck/boardman/actions/workflows/board-man-ci.yml/badge.svg)](https://github.com/uniplanck/boardman/actions/workflows/board-man-ci.yml)
[![Latest release](https://img.shields.io/github/v/release/uniplanck/boardman?display_name=tag&sort=semver)](https://github.com/uniplanck/boardman/releases/latest)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-111111?logo=apple)](https://github.com/uniplanck/boardman/releases/latest)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](../../LICENSE)

[ダウンロード](#ダウンロード) · [機能](#主な機能) · [変更履歴](../../CHANGELOG.md) · [ビルド](#ソースからビルド) · [コントリビュート](../../.github/CONTRIBUTING.md) · [English](../../README.md)

</div>

![安全なデモデータを表示したBoard-Man](../assets/screenshots/board-man-history-ja.png)

Board-Manは、[Clipy](https://github.com/Clipy/Clipy)から派生したmacOS向けクリップボード生産性アプリです。テキスト、URL、コマンド、定型文、画像をアプリ間で繰り返し扱う作業を、メニューバーからすぐ再開できます。

クリップボード履歴はMac内で扱われ、クラウド同期サービスを必須としません。

> **リリース状況:** 現在ダウンロードできる最新版は **v1.2.3** です。`main`ブランチは継続開発中で、タグ付きリリースには未収録の機能を含む場合があります。

## Board-Manを使う理由

一般的なクリップボード管理は「何をコピーしたか」を残します。Board-Manはさらに「何を繰り返し使っているか」「何を定型文にすべきか」を見つけやすくします。

- `⌘⌥V`で履歴を即座に開く
- 重要な項目をPinして整理対象から保護する
- 再利用する文章を**定型文**として保存する
- 使用回数から頻繁に使う項目を把握する
- 検索とキーボード操作で作業から離れず貼り付ける
- テキスト、URL、コマンド、画像を同じ履歴で扱う
- 時刻表示、密度、外観、ショートカット、保持件数を調整する
- データを削除せず、パネル上の機密項目をマスクする

## 画面

<table>
  <tr>
    <td width="50%"><img src="../assets/screenshots/board-man-history-ja.png" alt="Board-Manの日本語履歴画面"></td>
    <td width="50%"><img src="../assets/screenshots/board-man-history-compact-en.png" alt="Board-Manの狭幅表示"></td>
  </tr>
  <tr>
    <td align="center"><strong>履歴</strong><br>検索、Pin、時刻、使用回数を一覧表示。</td>
    <td align="center"><strong>レスポンシブ表示</strong><br>横幅を狭めてもアクセサリの余白を維持。</td>
  </tr>
  <tr>
    <td colspan="2"><img src="../assets/screenshots/board-man-settings-en.png" alt="Board-Manの設定画面"></td>
  </tr>
</table>

## 主な機能

### クリップボード履歴

- メニューバーからテキスト、リンク、コマンド、画像の履歴を表示
- 検索、上下キー移動、直接貼り付け
- Pin済み項目を保護する保持件数設定
- 数値、単位、接尾辞、`now`表示を選べる相対時刻
- 項目ごとの表示名、ハイライト、マスク、期限付きPin

### 定型文

- 再利用する文章をグループで整理
- 表示名と内容を編集
- ドラッグ＆ドロップで並び替え
- グループショートカットと有効・無効状態

コード内部と上流由来の文脈では`snippet`という名称を残していますが、製品UIでは日本語を**定型文**、英語を**Templates**としています。

### 使用状況の可視化

- 貼り付け回数バッジ
- 使用済み項目の表示スタイル
- 一般的な画像名同士で使用回数が衝突しない画像識別

### ローカルファーストのプライバシー

- 履歴と定型文をローカルに保存
- 外部クリップボード同期を必須としない
- マスクはパネル表示を隠す機能であり、元データを削除したと偽装しない
- リポジトリ掲載スクリーンショットは、一時プロファイルと決め打ちのデモデータから自動生成し、実際の履歴を使用しない

## ダウンロード

現在の公開版は[Board-Man v1.2.3](https://github.com/uniplanck/boardman/releases/tag/v1.2.3)です。

1. `Board-Man-v1.2.3.zip`をダウンロード
2. ZIPを展開
3. `Board-Man.app`を`/Applications`へ移動
4. Board-Manを開く

初回起動をmacOSに止められた場合は、Control-clickして**開く**を選ぶか、**システム設定 → プライバシーとセキュリティ**から許可してください。

グローバルショートカットと安定した貼り付けには、アクセシビリティと入力監視の権限が必要です。macOSの案内に従って手動で許可してください。本プロジェクトはTCC保護を迂回しません。

## 基本操作

1. テキスト、URL、コマンド、画像をコピー
2. `⌘⌥V`またはメニューバーからBoard-Manを開く
3. 検索または上下キーで選択
4. Returnで貼り付け
5. 残したい項目をPinし、繰り返す文章を定型文へ保存

| 操作 | ショートカット |
|---|---|
| Board-Manを開く | `⌘⌥V` |
| 履歴 / 定型文 / 設定 | `⌘1` / `⌘2` / `⌘3` |
| 検索へ移動 | `⌘F` |
| 選択移動 | `↑` / `↓` |
| 選択項目を貼り付け | `Return` |
| 選択項目をコピー | `⌘C` |
| Pin切替 | `⌘P` |
| プレビュー | `Space` |

## 動作要件

- macOS 13以降
- Apple Silicon / Intel Mac
- 全機能にはアクセシビリティと入力監視の権限が必要

## ソースからビルド

現在のXcode、Git、Swift Package Managerへの接続が必要です。

```bash
git clone https://github.com/uniplanck/boardman.git
cd boardman
xcodebuild \
  -project Board-Man.xcodeproj \
  -scheme Board-Man \
  -configuration Debug \
  -destination 'platform=macOS' \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  build
```

テスト:

```bash
xcodebuild \
  -project Board-Man.xcodeproj \
  -scheme Board-Man \
  -configuration Debug \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  test
```

ローカル版の安定したインストールには[`scripts/boardman/install-dev-stable.sh`](../../scripts/boardman/install-dev-stable.sh)を使用し、[`docs/boardman-dev-install.md`](../boardman-dev-install.md)を確認してください。

## ドキュメント

- [変更履歴](../../CHANGELOG.md)
- [開発版インストール](../boardman-dev-install.md)
- [QAチェックリスト](../BOARDMAN_QA_CHECKLIST.md)
- [READMEスクリーンショット生成](../readme-screenshots.md)
- [リリース・更新設計](../boardman-release-update-spec.md)
- [Sparkle更新基盤](../sparkle-updates.md)
- [UIデザインシステム](../boardman-ui-design-system.md)

## コントリビュートとサポート

- [コントリビューションガイド](../../.github/CONTRIBUTING.md)
- [セキュリティポリシー](../../.github/SECURITY.md)
- [サポートガイド](../../.github/SUPPORT.md)
- [コミュニティ行動規範](../../.github/CODE_OF_CONDUCT.md)
- [Issueを開く](https://github.com/uniplanck/boardman/issues)

UI変更では、通常幅と狭幅の実画面を確認し、スクリーンショットを添えてください。既存のローカルデータを破壊しないことを最優先します。

## ライセンスと帰属

Board-ManはClipyを大きく変更した派生著作物で、上流プロジェクトの帰属表示とライセンスを保持します。

- [`ATTRIBUTION.md`](../../ATTRIBUTION.md)
- [`LICENSE`](../../LICENSE)
- [`LICENSE_CLIPMENU`](../../LICENSE_CLIPMENU)

Board-ManはClipyから継承したMITライセンス条件で配布されます。上流のClipyまたはClipMenuメンテナーによる承認を受けたものではありません。

リポジトリのFundingリンクは上流Clipyプロジェクトを支援するもので、Board-Man独自の支援先は現在掲載していません。
