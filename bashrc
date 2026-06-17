# ~/.bashrc

# Map friendly env names -> "subscription|resourceGroup|cluster"
azenv() {
  local target="${1:-dev}"
  local SUB RG CLUSTER

  case "$target" in
    dev)
      SUB="dev-sub-id";  RG="dev-rg";  CLUSTER="dev-aks" ;;
    prod)
      SUB="prod-sub-id"; RG="prod-rg"; CLUSTER="prod-aks" ;;
    *)
      echo "Unknown env: $target (use dev|prod)"; return 1 ;;
  esac

  if ! az account show >/dev/null 2>&1; then
    az login >/dev/null
  fi

  az account set --subscription "$SUB"
  az aks get-credentials -g "$RG" -n "$CLUSTER" --overwrite-existing
  kubelogin convert-kubeconfig -l azurecli

  echo "→ $target | sub: $(az account show --query name -o tsv) | ctx: $(kubectl config current-context)"
}
