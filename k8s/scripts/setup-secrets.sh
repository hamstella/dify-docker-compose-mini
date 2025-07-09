#!/bin/bash
set -e

echo "🔐 Setting up Dify Kubernetes secrets..."

# Check if required tools are installed
command -v openssl >/dev/null 2>&1 || { echo "❌ openssl is required but not installed. Aborting." >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl is required but not installed. Aborting." >&2; exit 1; }

# Generate secure passwords and keys
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

generate_secret_key() {
    openssl rand -base64 42 | tr -d "=+/"
}

echo "📝 Generating secure passwords and keys..."

# Generate passwords
DB_PASSWORD=$(generate_password)
REDIS_PASSWORD=$(generate_password)
SECRET_KEY=$(generate_secret_key)
WEAVIATE_API_KEY=$(generate_password)
QDRANT_API_KEY=$(generate_password)
SANDBOX_API_KEY=$(generate_password)
PLUGIN_DAEMON_KEY=$(generate_secret_key)
PLUGIN_INNER_API_KEY=$(generate_secret_key)

echo "🔧 Creating secret files from templates..."

# Create base secret file
sed -e "s/CHANGE_ME_TO_SECURE_SECRET_KEY/${SECRET_KEY}/g" \
    -e "s/CHANGE_ME_TO_SECURE_DB_PASSWORD/${DB_PASSWORD}/g" \
    -e "s/CHANGE_ME_TO_SECURE_REDIS_PASSWORD/${REDIS_PASSWORD}/g" \
    -e "s/CHANGE_ME_TO_SECURE_WEAVIATE_API_KEY/${WEAVIATE_API_KEY}/g" \
    -e "s/CHANGE_ME_TO_SECURE_QDRANT_API_KEY/${QDRANT_API_KEY}/g" \
    -e "s/CHANGE_ME_TO_SECURE_SANDBOX_API_KEY/${SANDBOX_API_KEY}/g" \
    -e "s/CHANGE_ME_TO_SECURE_PLUGIN_DAEMON_KEY/${PLUGIN_DAEMON_KEY}/g" \
    -e "s/CHANGE_ME_TO_SECURE_PLUGIN_INNER_API_KEY/${PLUGIN_INNER_API_KEY}/g" \
    base/secret.yaml.example > base/secret.yaml

# Create postgres secret file
sed -e "s/CHANGE_ME_TO_SECURE_POSTGRES_PASSWORD/${DB_PASSWORD}/g" \
    services/postgres/secret.yaml.example > services/postgres/secret.yaml

# Create redis secret file
sed -e "s/CHANGE_ME_TO_SECURE_REDIS_PASSWORD/${REDIS_PASSWORD}/g" \
    services/redis/secret.yaml.example > services/redis/secret.yaml

echo "✅ Secret files created successfully!"
echo ""
echo "📋 Generated credentials summary:"
echo "  - Database Password: ${DB_PASSWORD}"
echo "  - Redis Password: ${REDIS_PASSWORD}"
echo "  - Secret Key: ${SECRET_KEY:0:20}..."
echo "  - Weaviate API Key: ${WEAVIATE_API_KEY}"
echo "  - Qdrant API Key: ${QDRANT_API_KEY}"
echo "  - Sandbox API Key: ${SANDBOX_API_KEY}"
echo ""
echo "⚠️  IMPORTANT: Please save these credentials securely!"
echo "⚠️  The secret files are now ready for deployment but are ignored by git."
echo ""
echo "🚀 You can now deploy with: kubectl apply -k ."