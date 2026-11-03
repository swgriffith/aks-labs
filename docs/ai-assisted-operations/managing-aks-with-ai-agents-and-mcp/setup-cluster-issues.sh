#!/bin/bash
set -euo pipefail

# Script to break the cluster in interesting ways for troubleshooting practice
# If you're curious what this does, read the source code!
# If you get stuck, just run cleanup-cluster-issues.sh to restore the cluster

echo "🔧 Breaking cluster..."
echo ""

# Validate environment variables
if [[ -z "${AKS_NAME:-}" ]] || [[ -z "${RG_NAME:-}" ]] || [[ -z "${MI_NAME:-}" ]] || [[ -z "${AKS_OIDC_ISSUER_URL:-}" ]] || [[ -z "${AI_NAME:-}" ]]; then
  echo "❌ Error: AKS_NAME, RG_NAME, MI_NAME, AKS_OIDC_ISSUER_URL, and AI_NAME environment variables must be set"
  exit 1
fi

# Issue 1: NetworkPolicy blocking all ingress in pets namespace
kubectl apply -n pets -f - > /dev/null <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: pets
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

echo "✓ Issue 1 setup completed"

# Issue 2: Deploy ai-service with broken workload identity
# Uses an unquoted heredoc so AI_API_BASE is expanded at runtime
kubectl apply -n pets -f - > /dev/null <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ai-service
  namespace: pets
  annotations:
    azure.workload.identity/client-id: 00000000-0000-0000-0000-000000000000
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ai-service
  namespace: pets
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ai-service
  template:
    metadata:
      labels:
        app: ai-service
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: ai-service
      containers:
      - name: ai-service
        image: ghcr.io/pauldotyu/aks-store-demo/ai-service:b9f05b1
        ports:
        - containerPort: 5001
        env:
        - name: USE_AZURE_OPENAI
          value: "True"
        - name: USE_AZURE_AD
          value: "True"
        - name: AZURE_OPENAI_DEPLOYMENT_NAME
          value: "gpt-5-mini"
        - name: AZURE_OPENAI_ENDPOINT
          value: "${AI_API_BASE:-https://placeholder.openai.azure.com/}"
        - name: AZURE_OPENAI_API_VERSION
          value: "2024-12-01-preview"
        - name: TEMPERATURE
          value: "1"
        resources:
          requests:
            cpu: 20m
            memory: 50Mi
          limits:
            cpu: 50m
            memory: 128Mi
        startupProbe:
          httpGet:
            path: /health
            port: 5001
          initialDelaySeconds: 60
          failureThreshold: 3
          periodSeconds: 5
        readinessProbe:
          httpGet:
            path: /health
            port: 5001
          initialDelaySeconds: 3
          failureThreshold: 10
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health
            port: 5001
          initialDelaySeconds: 3
          failureThreshold: 10
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: ai-service
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 5001
      targetPort: 5001
  selector:
    app: ai-service
EOF

az identity federated-credential create \
--name pets-ai-service \
--identity-name $MI_NAME \
--resource-group $RG_NAME \
--issuer $AKS_OIDC_ISSUER_URL \
--subject system:serviceaccount:pets:ai-service \
--audiences api://AzureADTokenExchange > /dev/null

az role assignment create --role "Cognitive Services OpenAI User" \
--assignee-object-id $(az identity show -g $RG_NAME -n $MI_NAME --query principalId -o tsv) \
--assignee-principal-type ServicePrincipal \
--scope $(az cognitiveservices account show -n $AI_NAME -g $RG_NAME --query id -o tsv) > /dev/null

echo "✓ Issue 2 setup completed"

# # Issue 3: NSG rule blocking Azure DNS
# MANAGED_RG=$(az aks show \
#   --name "$AKS_NAME" \
#   --resource-group "$RG_NAME" \
#   --query nodeResourceGroup -o tsv 2> /dev/null)

# NODE_NSG=$(az network nsg list \
#   --resource-group "$MANAGED_RG" \
#   --query '[0].name' -o tsv 2> /dev/null)

# if [[ -z "$NODE_NSG" ]]; then
#   echo "❌ Error: Could not find NSG"
#   exit 1
# fi

# EXISTING_RULE=$(az network nsg rule list \
#   --resource-group "$MANAGED_RG" \
#   --nsg-name "$NODE_NSG" \
#   --query "[?name=='DenyAzureDNS'].name" -o tsv 2> /dev/null)

# if [[ -z "$EXISTING_RULE" ]]; then
#   az network nsg rule create \
#     --resource-group "$MANAGED_RG" \
#     --nsg-name "$NODE_NSG" \
#     --name DenyAzureDNS \
#     --direction Outbound \
#     --priority 100 \
#     --destination-address-prefixes "168.63.129.16" \
#     --access Deny \
#     --protocol '*' \
#     --destination-port-ranges '*' \
#     --source-address-prefixes '*' \
#     --source-port-ranges '*' > /dev/null
# fi

# echo "✓ Issue 3 setup completed"
echo ""
echo "✅ Cluster is now broken. Use agents to figure out what's wrong!"
echo "   (Hint: Check the source of this script if you get stuck)"
echo ""
