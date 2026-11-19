#!/usr/bin/env bash
# Installa Flux nel cluster k3d e lo collega al repository (GitOps).
# Idempotente: si può rieseguire senza danni.
#
# Prerequisiti:
#   - cluster attivo (scripts/cluster-up.sh)
#   - GITHUB_TOKEN nell'ambiente, con permesso di amministrare il repo (serve a
#     registrare la deploy key). Il token NON viene scritto su file né stampato.
#   - chiave privata age in ~/.config/sops/age/keys.txt (o SOPS_AGE_KEY_FILE)
#
# Uso: GITHUB_TOKEN=... scripts/flux-bootstrap.sh
# Variabili opzionali: CLUSTER_NAME (boutique), GITHUB_OWNER (RiCMasetti),
#                      GITHUB_REPO (online-boutique-platform)
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-boutique}"
CONTEXT="k3d-${CLUSTER_NAME}"
OWNER="${GITHUB_OWNER:-RiCMasetti}"
REPO="${GITHUB_REPO:-online-boutique-platform}"
AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

for tool in flux kubectl; do
  command -v "$tool" >/dev/null || { echo "Errore: '$tool' non trovato nel PATH" >&2; exit 1; }
done
[ -n "${GITHUB_TOKEN:-}" ] || { echo "Errore: GITHUB_TOKEN non impostato" >&2; exit 1; }
[ -f "$AGE_KEY_FILE" ] || { echo "Errore: chiave age non trovata in $AGE_KEY_FILE" >&2; exit 1; }
kubectl --context "$CONTEXT" get nodes >/dev/null || { echo "Errore: cluster '$CONTEXT' non raggiungibile" >&2; exit 1; }

flux check --pre --context "$CONTEXT" || true   # l'avviso sulla versione della CLI non è bloccante

# Il Secret con la chiave age va creato PRIMA che Flux provi a decifrare i Secret
# degli overlay. Passa per pipe: la chiave non viene mai stampata.
kubectl --context "$CONTEXT" create namespace flux-system --dry-run=client -o yaml \
  | kubectl --context "$CONTEXT" apply -f -
kubectl --context "$CONTEXT" -n flux-system create secret generic sops-age \
  --from-file=age.agekey="$AGE_KEY_FILE" --dry-run=client -o yaml \
  | kubectl --context "$CONTEXT" apply -f -

flux bootstrap github --context "$CONTEXT" \
  --owner="$OWNER" --repository="$REPO" --branch=main \
  --path=clusters/local --personal

echo "Flux installato. Stato:"
flux get kustomizations --context "$CONTEXT"
