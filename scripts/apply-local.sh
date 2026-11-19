#!/usr/bin/env bash
# Applica un overlay al cluster k3d SENZA Flux (uso fino alla fase 3).
# Non usarlo su un cluster gestito da Flux: i due si contenderebbero gli oggetti.
# Uso: scripts/apply-local.sh <dev|prod>
#
# Perché non `kubectl apply -k`: gli overlay contengono Secret cifrati con SOPS
# (*.enc.yaml). Applicarli così com'sono darebbe errore o, peggio, creerebbe un Secret con
# il testo cifrato come valore. Lo script decifra i Secret con la chiave age locale e li
# passa a kubectl via pipe (nessun file in chiaro su disco), poi applica il resto.
# Con Flux (docs/gitops.md) questo script non serve più: la decifratura la fa il controller.
set -euo pipefail

ENV="${1:?Uso: $0 <dev|prod>}"
CLUSTER_NAME="${CLUSTER_NAME:-boutique}"
CONTEXT="k3d-${CLUSTER_NAME}"
OVERLAY="deploy/overlays/${ENV}"
NS="boutique-${ENV}"
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

[ -d "$OVERLAY" ] || { echo "Overlay non trovato: $OVERLAY" >&2; exit 1; }
[ -r "$SOPS_AGE_KEY_FILE" ] || { echo "Chiave age non leggibile: $SOPS_AGE_KEY_FILE" >&2; exit 1; }
for tool in kustomize kubectl sops python3; do
  command -v "$tool" >/dev/null || { echo "Errore: '$tool' non trovato" >&2; exit 1; }
done

K=(kubectl --context "$CONTEXT")

echo "1/3 Namespace $NS"
"${K[@]}" apply -f "$OVERLAY/namespace.yaml"

echo "2/3 Secret cifrati (SOPS)"
for f in "$OVERLAY"/*.enc.yaml; do
  [ -e "$f" ] || continue
  sops --decrypt "$f" | "${K[@]}" apply -n "$NS" -f -
done

echo "3/3 Risorse dell'overlay (Secret cifrati esclusi)"
kustomize build "$OVERLAY" | python3 -c '
import sys
docs = sys.stdin.read().split("\n---\n")
# Esclude i documenti cifrati (hanno la chiave top-level "sops:").
keep = [d for d in docs if "\nsops:\n" not in "\n" + d]
sys.stdout.write("\n---\n".join(keep))
' | "${K[@]}" apply -f -

echo "Fatto. Controlla: kubectl --context $CONTEXT -n $NS get pods"
