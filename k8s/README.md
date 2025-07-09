# Dify Kubernetes Deployment

このディレクトリには、Docker ComposeからKubernetesに変換されたDifyアプリケーションのマニフェストファイルが含まれています。

## 構成概要

```
k8s/
├── base/                      # 基本リソース
│   ├── namespace.yaml         # difyネームスペース
│   ├── configmap.yaml         # 共通設定（非機密情報）
│   ├── secret.yaml            # 機密情報（パスワード、APIキーなど）
│   ├── pvc.yaml               # 共有ストレージ（20Gi）
│   ├── networkpolicy.yaml     # ネットワークポリシー
│   └── kustomization.yaml
├── services/                  # 各サービス
│   ├── postgres/              # PostgreSQL（StatefulSet）
│   ├── redis/                 # Redis（StatefulSet）
│   ├── api/                   # API サーバー
│   ├── worker/                # Celery Worker
│   ├── web/                   # Webフロントエンド
│   ├── sandbox/               # コード実行環境
│   ├── plugin-daemon/         # プラグインデーモン
│   ├── ssrf-proxy/           # SSRF対策プロキシ
│   └── nginx/                 # リバースプロキシ
└── kustomization.yaml         # 全体統合
```

## デプロイ方法

### 1. 前提条件

- Kubernetes クラスター（v1.20以上推奨）
- kubectl コマンドラインツール
- 適切なStorageClass（`standard`）
- LoadBalancer対応（クラウド環境の場合）

### 2. 機密情報の設定

デプロイ前に機密情報を設定する必要があります。以下のいずれかの方法で設定してください：

#### 方法1: 自動セットアップスクリプト（推奨）
```bash
cd k8s
./scripts/setup-secrets.sh
```

このスクリプトは安全なランダムパスワードとキーを自動生成し、テンプレートファイルから実際のsecret.yamlファイルを作成します。

#### 方法2: 手動設定
```bash
# テンプレートファイルをコピー
cp base/secret.yaml.example base/secret.yaml
cp services/postgres/secret.yaml.example services/postgres/secret.yaml
cp services/redis/secret.yaml.example services/redis/secret.yaml

# 各ファイルでプレースホルダーを実際の値に置換
# 例: CHANGE_ME_TO_SECURE_SECRET_KEY を実際のキーに変更
```

⚠️ **重要**: 
- 本番環境では必ず強力な独自のパスワードとキーを使用してください
- secret.yamlファイルはgitの管理対象外になっています
- 生成された認証情報は安全に保管してください

#### `base/configmap.yaml`
```yaml
# 必要に応じて変更
CONSOLE_API_URL: "https://your-domain.com"
APP_API_URL: "https://your-domain.com"
```

#### `services/nginx/service.yaml`
```yaml
# 環境に応じてServiceTypeを変更
spec:
  type: LoadBalancer  # NodePort, ClusterIP, LoadBalancer
```

### 3. デプロイの実行

```bash
# 機密情報の設定（まだ実行していない場合）
cd k8s
./scripts/setup-secrets.sh

# 全体デプロイ
kubectl apply -k .

# 特定のサービスのみデプロイ
kubectl apply -k services/postgres/
```

### 4. デプロイ状況の確認

```bash
# Pod状態確認
kubectl get pods -n dify

# サービス確認
kubectl get svc -n dify

# PVC確認
kubectl get pvc -n dify

# ログ確認
kubectl logs -n dify deployment/api -f
```

## サービス詳細

### データベース層

#### PostgreSQL (`postgres/`)
- **タイプ**: StatefulSet
- **レプリカ数**: 1
- **ストレージ**: 10Gi
- **ポート**: 5432
- **用途**: メインデータベース

#### Redis (`redis/`)
- **タイプ**: StatefulSet
- **レプリカ数**: 1
- **ストレージ**: 5Gi
- **ポート**: 6379
- **用途**: キャッシュ、セッション、Celeryブローカー

### アプリケーション層

#### API Server (`api/`)
- **タイプ**: Deployment
- **レプリカ数**: 1
- **ポート**: 5001
- **用途**: REST API エンドポイント

#### Worker (`worker/`)
- **タイプ**: Deployment
- **レプリカ数**: 1
- **用途**: Celery バックグラウンドタスク処理

#### Web Frontend (`web/`)
- **タイプ**: Deployment
- **レプリカ数**: 2
- **ポート**: 3000
- **用途**: Next.js フロントエンド

### 補助サービス

#### Sandbox (`sandbox/`)
- **タイプ**: Deployment
- **レプリカ数**: 1
- **ポート**: 8194
- **用途**: コード実行環境
- **セキュリティ**: 非root実行、権限制限

#### Plugin Daemon (`plugin-daemon/`)
- **タイプ**: Deployment
- **レプリカ数**: 1
- **ポート**: 5002, 5003
- **用途**: プラグイン管理

#### SSRF Proxy (`ssrf-proxy/`)
- **タイプ**: Deployment
- **レプリカ数**: 1
- **ポート**: 3128, 8194
- **用途**: SSRF攻撃対策

#### Nginx (`nginx/`)
- **タイプ**: Deployment
- **レプリカ数**: 2
- **ポート**: 80, 443
- **用途**: リバースプロキシ、ロードバランサー

## ネットワーク構成

### NetworkPolicy

SSRF攻撃対策のため、以下のネットワーク分離を実装：

- `ssrf-proxy-network`: 内部ネットワーク（sandbox、ssrf-proxy、api）
- 外部アクセス制限: DNS以外の外部通信を制限

### サービス間通信

```
Internet → Nginx → API/Web
                ↓
            Database/Redis
                ↓
        Sandbox ← SSRF Proxy
```

## ストレージ

### PersistentVolumes

1. **dify-storage** (20Gi, ReadWriteMany)
   - API、Worker間で共有
   - ユーザーファイル、ログ保存

2. **postgres-data** (10Gi, ReadWriteOnce)
   - PostgreSQL データディレクトリ

3. **redis-data** (5Gi, ReadWriteOnce)
   - Redis データディレクトリ

4. **sandbox-dependencies** (5Gi, ReadWriteOnce)
   - Sandbox依存関係

5. **sandbox-conf** (1Gi, ReadWriteOnce)
   - Sandbox設定ファイル

6. **plugin-storage** (10Gi, ReadWriteOnce)
   - プラグイン関連ファイル

## セキュリティ考慮事項

### 1. 機密情報管理

- パスワード、APIキーは`Secret`で管理
- 本番環境では必ず値を変更
- RBAC（Role-Based Access Control）の設定推奨

### 2. ネットワークセキュリティ

- NetworkPolicyによる通信制限
- 不要なポートの公開回避
- TLS/SSL証明書の設定（Nginx）

### 3. Pod セキュリティ

- 非root実行（Sandbox）
- ReadOnlyRootFilesystem（可能な限り）
- Security Context の適切な設定

## 運用・監視

### ヘルスチェック

全サービスでLiveness/ReadinessProbeを設定：

- **HTTP**: API、Web、Nginx、Sandbox
- **TCP**: PostgreSQL、Redis、SSRF Proxy
- **Exec**: Worker（Celery）、Plugin Daemon

### ログ管理

```bash
# 各サービスのログ確認
kubectl logs -n dify deployment/api -f
kubectl logs -n dify deployment/worker -f
kubectl logs -n dify deployment/web -f
```

### スケーリング

```bash
# レプリカ数変更
kubectl scale deployment/web --replicas=3 -n dify
kubectl scale deployment/api --replicas=2 -n dify
```

## トラブルシューティング

### 1. Pod起動失敗

```bash
# Pod状態確認
kubectl get pods -n dify
kubectl describe pod <pod-name> -n dify

# イベント確認
kubectl get events -n dify --sort-by=.metadata.creationTimestamp
```

### 2. ストレージ問題

```bash
# PVC状態確認
kubectl get pvc -n dify
kubectl describe pvc <pvc-name> -n dify

# StorageClass確認
kubectl get storageclass
```

### 3. ネットワーク問題

```bash
# Service確認
kubectl get svc -n dify
kubectl get endpoints -n dify

# NetworkPolicy確認
kubectl get networkpolicy -n dify
```

### 4. 設定問題

```bash
# ConfigMap確認
kubectl get configmap -n dify
kubectl describe configmap dify-config -n dify

# Secret確認
kubectl get secrets -n dify
```

## アップデート方法

```bash
# 設定変更の適用
kubectl apply -k k8s/

# 特定サービスの再起動
kubectl rollout restart deployment/api -n dify

# ロールアウト状況確認
kubectl rollout status deployment/api -n dify
```

## バックアップ

### データベースバックアップ

```bash
# PostgreSQL バックアップ
kubectl exec -n dify postgresql-0 -- pg_dump -U postgres dify > backup.sql

# Redis バックアップ
kubectl exec -n dify redis-0 -- redis-cli BGSAVE
```

### 設定バックアップ

```bash
# 全体設定エクスポート
kubectl get all,configmap,secret,pvc -n dify -o yaml > dify-backup.yaml
```

## 本番環境への移行時の注意点

1. **リソース要件の調整**
   - CPU/メモリ制限を本番負荷に合わせて調整
   - ストレージサイズの適切な設定

2. **高可用性の確保**
   - 複数ノードでのPod分散
   - データベースの冗長化検討

3. **監視・アラート**
   - Prometheus/Grafana等の監視システム導入
   - ログ集約システムの構築

4. **セキュリティ強化**
   - RBAC設定
   - Pod Security Standards適用
   - イメージスキャンの実装

5. **バックアップ戦略**
   - 定期的なデータベースバックアップ
   - 設定の版管理

## 参考リンク

- [Kubernetes公式ドキュメント](https://kubernetes.io/docs/)
- [Dify公式ドキュメント](https://docs.dify.ai/)
- [Kustomize](https://kustomize.io/)