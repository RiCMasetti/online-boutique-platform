#!/usr/bin/env bash
# Crea (se manca) il cluster k3d locale e attende che sia pronto.
# Uso: scripts/cluster-up.sh
# Variabili opzionali: CLUSTER_NAME (default: boutique), HOST_PORT (default: 8080)
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-boutique}"
HOST_PORT="${HOST_PORT:-8080}"
CONTEXT="k3d-${CLUSTER_NAME}"

for tool in docker k3d kubectl; do
  command -v "$tool" >/dev/null || { echo "Errore: '$tool' non trovato nel PATH" >&2; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "Errore: il daemon Docker non risponde" >&2; exit 1; }

if k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$CLUSTER_NAME"; then
  echo "Il cluster '$CLUSTER_NAME' esiste già, lo riuso."
  k3d cluster start "$CLUSTER_NAME" >/dev/null 2>&1 || true
else
  echo "Creo il cluster '$CLUSTER_NAME' (porta host ${HOST_PORT} -> Traefik :80)..."
  # Un solo nodo server, Traefik di k3s incluso (ingress).
  k3d cluster create "$CLUSTER_NAME" \
    --servers 1 --agents 0 \
    --port "${HOST_PORT}:80@loadbalancer" \
    --wait
fi

# Da qui in poi si usa sempre --context esplicito, mai il context corrente.
echo "Attendo il nodo e Traefik..."
kubectl --context "$CONTEXT" wait --for=condition=Ready node --all --timeout=120s
# Traefik viene installato da k3s con un job Helm, dopo che il nodo è Ready:
# il Deployment può non esistere ancora, quindi si attende prima la sua comparsa.
for _ in $(seq 1 60); do
  kubectl --context "$CONTEXT" -n kube-system get deployment/traefik >/dev/null 2>&1 && break
  sleep 2
done
kubectl --context "$CONTEXT" -n kube-system rollout status deployment/traefik --timeout=180s

echo "Cluster pronto. Context: $CONTEXT"
