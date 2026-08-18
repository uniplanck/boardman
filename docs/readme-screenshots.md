# README Screenshot Workflow

Board-ManのREADME画像は、隔離した一時プロファイルと決め打ちのデモデータから自動生成します。通常利用中のクリップボード履歴、定型文、顧客情報、token、ローカルパス、認証情報をGitへ混入させないための手順です。

## 生成する画像

実行すると次の画像を更新します。

- `docs/assets/screenshots/board-man-history-en.png`
- `docs/assets/screenshots/board-man-templates-en.png`
- `docs/assets/screenshots/board-man-settings-en.png`
- `docs/assets/screenshots/board-man-history-compact-en.png`
- `docs/assets/screenshots/board-man-history-ja.png`
- `docs/assets/screenshots/board-man-templates-ja.png`
- `docs/assets/screenshots/board-man-settings-ja.png`
- `docs/assets/screenshots/board-man-history-compact-ja.png`
- `docs/assets/board-man-main-screenshot.png`
- `assets/readme/board-man-screenshot.png`

末尾2ファイルは、既存ドキュメントとの互換性を保つ別名です。

## 安全設計

撮影スクリプトは次の順序で動きます。

1. `/Applications/Board-Man.app`が起動中か記録する
2. 撮影中の競合を避けるためBoard-Manを停止する
3. 各シーン専用の一時`HOME`と`CFFIXED_USER_HOME`を作る
4. クリップボードを英語または日本語の固定デモ内容へ差し替える
5. 定型文シーンではDebug専用コードが固定デモグループと定型文を一時Realmへ追加する
6. 明示的な撮影用環境変数を付けてDebug版Board-Manを起動する
7. デスクトップ全体ではなく、Board-Manのパネル内容だけをPNGへ書き出す
8. 画像の存在と寸法を確認する
9. 一時プロファイルをすべて削除する
10. クリップボードへ無害な完了メッセージを残す
11. 撮影前に通常版が起動していた場合だけ再起動する

アプリ側の書き出し処理はDebugビルドだけに含まれ、`BOARDMAN_SCREENSHOT_OUTPUT`が指定された時だけ動きます。Releaseビルドや通常起動では、パネルの自動表示・自動保存・デモデータ作成を行いません。

## 必要環境

- macOS 13以降
- Xcode
- 現在のソースから作成したDebug版Board-Man
- ローカルのBoard-Manを一時停止・再起動する許可

## Debug版をビルド

```bash
xcodebuild \
  -project Board-Man.xcodeproj \
  -scheme Board-Man \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  build
```

## README画像を生成

現在のcheckoutから生成されたアプリを明示して実行します。

```bash
APP_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
  -path '*/Build/Products/Debug/Board-Man.app' \
  -type d \
  -print \
  | head -n 1)"

BOARDMAN_SCREENSHOT_APP="$APP_PATH" \
  ./scripts/boardman/capture-readme-screenshots.sh
```

`APP_PATH`が現在のcheckoutから作成されたものか確認してください。新しいUIを説明する時に、古いインストール済みアプリへ黙ってフォールバックしてはいけません。

出力先を変更する場合:

```bash
BOARDMAN_SCREENSHOT_OUTPUT_DIR=/tmp/boardman-screenshots \
  BOARDMAN_SCREENSHOT_APP=/path/to/Board-Man.app \
  ./scripts/boardman/capture-readme-screenshots.sh
```

## デモ内容

履歴シーンには、次の種類を含む英語・日本語の固定例を使います。

- 既定ショートカット
- 打ち合わせメモ
- ローカルファーストの説明
- デザイン確認項目
- 公開リポジトリURL
- 無害なGitコマンド
- 返信文
- リリース確認

定型文シーンには、返信、開発、リンクのデモグループを使います。実際の顧客メッセージ、非公開URL、token、パスワード、秘密鍵、ローカルファイルパスへ置き換えないでください。

## 検証

```bash
bash -n scripts/boardman/capture-readme-screenshots.sh
find docs/assets/screenshots -maxdepth 1 -name 'board-man-*.png' -type f -print | sort
```

生成後は8枚すべてを確認します。

- 固定デモ内容以外が表示されていない
- 英語・日本語の履歴、定型文、設定、コンパクト表示が揃っている
- Pin、時刻、本文、境界線、ボタン、タブが切れていない
- コンパクト表示でもPinと時刻の左右余白が残っている
- 日本語では「定型文」、英語では「Templates」と表示される
- 定型文画面にデモグループと選択中の内容が表示される
- 画像寸法が0ではなく、指定したシーンサイズと整合する

スクリプトの終了コードが0でも、見た目が正しいとは限りません。PNG生成確認に加えて、実画像の目視確認を必須とします。
