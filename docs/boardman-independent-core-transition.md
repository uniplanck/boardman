# Board-Man Independent Core Transition

Status: in progress

## Goal

Board-Manを、旧Clipy / ClipMenu由来コード・資産・ブランド依存を含まない独立実装へ段階的に移行し、移行完了後にBoard-Man自身のMITライセンスへ切り替える。

この文書は移行計画であり、現時点のルート`LICENSE`を置き換えるものではない。旧由来コードが残る間は既存の著作権表示とライセンス通知を保持する。

## Target licensing model

### MIT licensed client

独立化完了後のBoard-Man macOSクライアントはMITライセンスを目標とする。

MIT対象に含めるもの:

- macOSクライアントの基本UI
- ローカルのクリップボード履歴
- Pin / 定型文 / 検索
- ローカル設定
- Appearance設定
- Import / Export
- ローカルPaste analytics
- 公開されたクライアント側ライセンス検証コード
- 公開されたcommercial service protocol contract
- 公開ドキュメントとビルド手順

ローカル機能は商用Entitlementで利用停止しない。MITライセンスでは第三者による利用、改変、再配布、商用利用を許可するため、公開クライアント内だけでPro制限を維持しようとする設計は採用しない。

### Non-public commercial services

サブスクリプションの継続的な価値と運用上の秘密情報は、MITクライアントの外側に置く。

非公開を前提とするもの:

- 課金 / 請求処理
- アカウント管理
- ライセンス発行API
- 署名用秘密鍵
- 不正利用対策のサーバー実装
- クラウド同期
- クラウドバックアップ
- AI処理
- チーム共有
- APIサービス
- 商用サポート運用
- 運用管理画面
- 顧客データ

クライアント側には公開鍵と検証ロジックだけを含め、署名秘密鍵は含めない。

Public client contract is documented in `docs/boardman-commercial-service-contract.md`.

## Commercial entitlement boundary

既存tokenとの互換性を保つため、旧local feature claim名はparse可能な状態を維持する。ただし以下のlocal capabilityはEntitlement有無に関係なく利用可能とする。

- `unlimitedHistory`
- `unlimitedSnippets`
- `advancedAppearance`
- `exportImport`
- `pasteAnalytics`

以下は外部サービスを必要とするためcommercial entitlement対象とする。

- `futureSync`
- `cloudBackup`
- `aiAssist`
- `teamSharing`
- `accountServices`
- `apiAccess`
- `commercialSupport`

Free snapshotのhistory / pinned / snippet / folder entitlement limitはすべてunlimitedとし、保存件数の制限が必要な場合はユーザー設定やストレージ保護ポリシーとして扱う。

## Brand boundary

MITはソースコードの利用許諾であり、Board-Manの名称、ロゴ、公式配布物であることを自動的に第三者へ許諾するものではない。公式配布物・公式サービス・公式ブランドの扱いはソフトウェアライセンスと分離する。

## Current transition state

2026-08-21時点で、外部Clipy-org package依存の除去と一部の非永続型・runtime utilityのBoard-Man実装への置換まで進んでいる。

### Completed independence work

- LoginServiceKit -> `SMAppService`
- Screeen -> Board-Man screenshot observer
- Magnet / Sauce / KeyHolder -> Board-Man AppKit + Carbon shortcut implementation
- `CPYAppInfo` active symbol -> `BoardManApplicationInfo`
- `CPYDraggedData` active symbol -> `BoardManDragPayload`
- `CPYUtilities` active symbol -> `BoardManRuntimeSupport`
- commercial-service client boundary implemented
- local MIT capabilities removed from commercial entitlement gating
- subscription/trial/owner ES256 token verification supported

既存除外アプリ設定などの互換性が必要な箇所ではlegacy archiveを読み取るmigration aliasを使用する。これは旧実装を残すためではなく、既存ユーザーデータを失わないための移行専用互換処理とする。

## Remaining provenance state

主な残存範囲:

- 旧Clipy著作権ヘッダを持つソース群
- Realm永続モデル `CPYClip`, `CPYFolder`, `CPYSnippet`
- archived clipboard payload `CPYClipData`
- `ClipService`, `PasteService`, `HotKeyService`, `MenuManager`などの中核
- preference / snippet controller・viewの旧identifier
- XIBの旧module名や旧identifier
- `Clipy/` source tree名
- Xcode target / project metadataの旧名称
- `LICENSE`, `LICENSE_CLIPMENU`, `ATTRIBUTION.md`

この状態では、ルート`LICENSE`から旧著作権表示を削除しない。

## Migration gates

### Gate 1: Board-Man-owned code cleanup

Git履歴でBoard-Man側の新規実装と確認できるファイルから、誤って残った旧テンプレート表記を除去する。

### Gate 2: External package independence

Completed for the five Clipy-org dependencies listed above. Build / test verification remains part of final gates.

### Gate 3: Data model rewrite

`CPYClip`, `CPYClipData`, `CPYFolder`, `CPYSnippet`等をBoard-Man独自モデルへ置換し、既存ユーザーデータを安全に移行できるmigrationを用意する。

Realm class nameは保存スキーマ名として使われるため、単純renameは禁止する。旧schemaをproperty shapeから読み取り、新Board-Man schemaへデータをコピーするmigrationを先に用意する。既存インストールからの履歴・定型文・folderデータ保全を優先する。

### Gate 4: Core service rewrite

少なくとも以下を独立実装へ置換する。

- clipboard monitoring
- paste / copy execution
- global shortcut handling
- history cleanup
- excluded app handling
- accessibility handling

### Gate 5: UI / project identity rewrite

- `Clipy/` source treeを廃止
- `CPY*` identifiersを廃止
- XIB / module / scheme / project referencesの旧名称を廃止
- 旧ブランド由来画像・資産を廃止

### Gate 6: License cutover

以下をすべて満たした後にのみBoard-Man MITへ切り替える。

1. `rg -i 'clipy|clipmenu|CPY'`の残存を、移行履歴など意図した非配布資料を除き0件にする。
2. 旧著作権ヘッダを持つ実装が配布ターゲットから0件であることを確認する。
3. 旧由来ライブラリ / 資産が配布ターゲットから外れていることを確認する。
4. clean build / test / local release installを通す。
5. 配布バイナリのversion / bundle ID / codesign /実行パスを確認する。
6. `LICENSE_BOARDMAN_MIT_DRAFT`をルート`LICENSE`へ昇格する。
7. 不要になった旧ライセンス・帰属ファイルを削除する。

## Release rule

独立化途中のbuildを、旧帰属を削除した状態で公開しない。ライセンス切り替えは最後のgateとして扱う。
