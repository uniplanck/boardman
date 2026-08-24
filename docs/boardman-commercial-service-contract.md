# Board-Man Commercial Service Contract

Status: client boundary implemented, private service pending

## Purpose

Board-ManのmacOSクライアントはMITで公開する一方、課金、アカウント、ライセンス発行、不正利用対策、クラウド同期、AI、チーム機能、バックアップ、APIなど継続的な商用サービスは非公開インフラとして分離する。

公開クライアントには秘密鍵を含めない。クライアントは公開鍵を使って、非公開サービスが発行したES256署名済みEntitlement tokenだけを検証する。

## Local MIT capabilities

以下は商用Entitlementの有無で利用を止めない。

- ローカル履歴
- Pin
- 定型文
- 検索
- Appearance設定
- Import / Export
- ローカルPaste analytics
- その他、ネットワークサービスを必要としないBoard-Manクライアント機能

既存tokenとの互換性のため、旧feature claim名はparseできる状態を維持するが、ローカル機能の利用判定には使わない。

## Commercial service capabilities

以下は署名済みEntitlementが必要なservice-backed capabilityとして扱う。

- `futureSync`
- `cloudBackup`
- `aiAssist`
- `teamSharing`
- `accountServices`
- `apiAccess`
- `commercialSupport`

## Activation endpoint

The public client expects:

`POST /v1/licenses/activate`

Base URL is intentionally not hard-coded. It is supplied through either:

- environment variable: `BOARD_MAN_COMMERCIAL_SERVICE_BASE_URL`
- app Info.plist key: `BoardManCommercialServiceBaseURL`

Request JSON:

```json
{
  "license_key": "USER-SUPPLIED-LICENSE-KEY",
  "device_id": "LOCAL-STABLE-UUID",
  "bundle_id": "com.uniplanck.BoardMan",
  "client_version": "0.x.y"
}
```

Successful response JSON:

```json
{
  "status": "activated",
  "message": "Activated",
  "signed_token": "<compact ES256 token>"
}
```

The service may return a non-2xx status with a human-readable `message`. The client treats non-2xx responses as rejected activation attempts.

## Token trust boundary

The client accepts a token only after all applicable checks pass:

1. compact token format is valid
2. `alg` is `ES256`
3. signature validates against the embedded public key
4. token is not expired
5. `device_id` matches the local stable device ID when supplied
6. `bundle_id` matches Board-Man
7. token version is supported
8. plan / license kind / state claims form a valid combination

Supported commercial claim shapes:

### Subscription / trial

- `license_kind = pro`
- `plan = pro`
- `state = proActive` or `trial`
- `is_lifetime = false`
- `exp` is required
- `token_version = 1`

### Owner lifetime

- `license_kind = ownerLifetime`
- `plan = ownerLifetime`
- `state = ownerLifetime`
- `is_lifetime = true`
- `exp` is absent
- `token_version = 1`

Only verified tokens are written to local state and applied to the runtime Entitlement snapshot.

## Private service responsibilities

The private service, not this public repository, owns:

- billing provider integration
- customer/account database
- subscription state
- activation / revocation policy
- device limits
- abuse / fraud controls
- ES256 signing private key
- cloud data encryption/storage policy
- sync implementation
- AI provider credentials and routing
- team membership / invitation state
- API credentials / quotas
- support tooling and operator admin UI

## Secret handling

Never commit any of the following to the public Board-Man repository:

- ES256 private key
- Stripe or other billing secrets
- database credentials
- AI provider API keys
- admin credentials
- customer records
- fraud rules that require secrecy

The public verification key is not secret and may remain in the MIT client.

## Repository boundary

This repository contains only the public client and the public protocol contract. A production commercial backend should live in a separate private repository and deployment environment.
