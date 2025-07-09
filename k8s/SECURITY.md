# セキュリティガイド

このドキュメントは、Dify Kubernetes デプロイメントのセキュリティベストプラクティスについて説明します。

## 機密情報の管理

### 1. Secret ファイルの取り扱い

- **❌ 絶対にしないこと**:
  - 実際の `secret.yaml` ファイルをGitにコミットしない
  - プレーンテキストでパスワードを共有しない
  - デフォルトのパスワードを本番環境で使用しない

- **✅ 推奨する方法**:
  - `setup-secrets.sh` スクリプトを使用してランダムなパスワードを生成
  - 機密情報は暗号化されたパスワードマネージャーで管理
  - 定期的なパスワードローテーションの実施

### 2. 強力なパスワードの生成

```bash
# 強力なパスワードの生成例
openssl rand -base64 32 | tr -d "=+/" | cut -c1-32

# Secret Key の生成例
openssl rand -base64 42 | tr -d "=+/"
```

### 3. 環境別の設定

本番環境、ステージング環境、開発環境で異なる認証情報を使用してください。

## Kubernetes セキュリティ

### 1. RBAC (Role-Based Access Control)

最小権限の原則に基づいてRBACを設定：

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: dify
  name: dify-operator
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets"]
  verbs: ["get", "list", "watch", "update"]
```

### 2. Network Policies

SSRF攻撃対策のため、以下のネットワークポリシーを適用：

- Sandbox、API、SSRF Proxyは内部ネットワークに分離
- 外部通信はDNSのみ許可
- 不要なポート間通信を遮断

### 3. Pod Security Standards

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dify
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

## アプリケーションセキュリティ

### 1. コンテナセキュリティ

- **非rootユーザーで実行**: 特にSandboxサービス
- **ReadOnlyRootFilesystem**: 可能な限り有効化
- **必要最小限のCapabilities**: 不要な権限を削除

### 2. 機密情報の暗号化

Kubernetesクラスターで etcd の暗号化を有効化：

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  - configmaps
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: <base64-encoded-key>
```

### 3. イメージセキュリティ

- **信頼できるレジストリ**: 公式イメージまたは検証済みイメージのみ使用
- **定期的なスキャン**: 脆弱性スキャンツールの使用
- **イメージの署名検証**: コンテナイメージの整合性確認

## 監視とログ

### 1. セキュリティログの監視

```bash
# 認証失敗の監視
kubectl logs -n dify deployment/api | grep -i "auth\|login\|fail"

# 異常なアクセスパターンの検出
kubectl logs -n dify deployment/nginx | grep -E "40[0-9]|50[0-9]"
```

### 2. アラート設定

- 複数回の認証失敗
- 異常な通信量
- Pod の再起動頻度
- リソース使用率の急激な変化

## インシデント対応

### 1. 緊急時の対応

```bash
# 緊急時のサービス停止
kubectl scale deployment/api --replicas=0 -n dify

# ネットワーク分離
kubectl patch networkpolicy default-deny-all -n dify -p '{"spec":{"podSelector":{}}}'

# 不正なPodの削除
kubectl delete pod <suspicious-pod> -n dify --force
```

### 2. 認証情報の漏洩時の対応

1. **即座に影響を受けるサービスを停止**
2. **新しい認証情報を生成**
3. **Secretを更新**
4. **関連するセッションを無効化**
5. **ログを確認して影響範囲を特定**

```bash
# 新しい認証情報でSecretを更新
kubectl patch secret dify-secret -n dify -p '{"data":{"SECRET_KEY":"<new-base64-encoded-key>"}}'

# Pod を再起動して新しい認証情報を反映
kubectl rollout restart deployment/api -n dify
```

## 定期的なセキュリティチェック

### 1. 週次チェック

- [ ] 不要なPodやサービスの確認
- [ ] リソース使用量の監視
- [ ] ログの異常確認

### 2. 月次チェック

- [ ] 依存関係の脆弱性スキャン
- [ ] ネットワークポリシーの見直し
- [ ] アクセス権限の棚卸し

### 3. 四半期チェック

- [ ] 認証情報のローテーション
- [ ] セキュリティポリシーの更新
- [ ] ペネトレーションテストの実施

## 参考リンク

- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [OWASP Container Security Top 10](https://owasp.org/www-project-container-security/)
- [Dify Security Documentation](https://docs.dify.ai/getting-started/install-self-hosted/docker-compose#security-considerations)