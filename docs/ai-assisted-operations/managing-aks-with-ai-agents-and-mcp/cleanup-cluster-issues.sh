#!/bin/bash
set -euo pipefail

# Script to clean up intentional cluster issues after troubleshooting lab
# This script removes the broken resources

echo "🧹 Cleaning up cluster issues..."
echo ""

# Validate environment variables
if [[ -z "${AKS_NAME:-}" ]] || [[ -z "${RG_NAME:-}" ]]; then
  echo "❌ Error: AKS_NAME and RG_NAME environment variables must be set"
  exit 1
fi

# ============================================================================
# Remove NetworkPolicy from pets namespace
# ============================================================================
echo "🗑️  Removing NetworkPolicy from pets namespace..."

if kubectl delete networkpolicy deny-all-ingress -n pets 2>/dev/null; then
  echo "✓ NetworkPolicy 'deny-all-ingress' removed"
else
  echo "⚠️  NetworkPolicy 'deny-all-ingress' not found (already removed?)"
fi

echo ""

# ============================================================================
# Remove custom ai-service resources
# ============================================================================
echo "🗑️  Removing custom ai-service resources..."

if kubectl delete deployment ai-service -n pets 2>/dev/null; then
  echo "✓ Custom ai-service Deployment removed"
else
  echo "⚠️  Custom ai-service Deployment not found (already removed?)"
fi

if kubectl delete service ai-service -n pets 2>/dev/null; then
  echo "✓ Custom ai-service Service removed"
else
  echo "⚠️  Custom ai-service Service not found (already removed?)"
fi

if kubectl delete serviceaccount ai-service -n pets 2>/dev/null; then
  echo "✓ Custom ai-service ServiceAccount removed"
else
  echo "⚠️  Custom ai-service ServiceAccount not found (already removed?)"
fi

echo ""

# # ============================================================================
# # Remove NSG rule blocking Azure DNS
# # ============================================================================
# echo "🗑️  Removing DenyAzureDNS rule from NSG..."

# MANAGED_RG=$(az aks show \
#   --name "$AKS_NAME" \
#   --resource-group "$RG_NAME" \
#   --query nodeResourceGroup -o tsv)

# NODE_NSG=$(az network nsg list \
#   --resource-group "$MANAGED_RG" \
#   --query '[0].name' -o tsv)

# if [[ -z "$NODE_NSG" ]]; then
#   echo "⚠️  Could not find NSG in managed resource group $MANAGED_RG"
# else
#   if az network nsg rule delete \
#     --resource-group "$MANAGED_RG" \
#     --nsg-name "$NODE_NSG" \
#     --name DenyAzureDNS 2>/dev/null; then
#     echo "✓ NSG rule 'DenyAzureDNS' removed from $NODE_NSG"
#   else
#     echo "⚠️  NSG rule 'DenyAzureDNS' not found (already removed?)"
#   fi
# fi

echo ""
echo "✅ Cleanup complete!"
echo "   Cluster is back to normal state"
echo ""
