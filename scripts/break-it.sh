#!/usr/bin/env bash
# Provoca guasti riproducibili in dev, per esercitare diagnosi e rollback (fase 8).
#
# Uso: scripts/break-it.sh <scenario>|restore|status
#
# Scenari:
#   image-tag     frontend con un tag di immagine inesistente        -> ImagePullBackOff
#   bad-addr      frontend con indirizzo di productcatalog sbagliato -> pod Ready, errori 500
#   missing-addr  checkoutservice senza SHIPPING_SERVICE_ADDR        -> CrashLoopBackOff
#   low-memory    currencyservice con limite di memoria di 16Mi      -> OOMKilled
#   frontend-down frontend a 0 repliche                              -> shop irraggiungibile
#
# Come funziona: sospende la Kustomization Flux di dev (altrimenti Flux annulla il guasto
# al giro successivo, ogni 10 minuti) e poi modifica il cluster con kubectl. Non tocca Git.
# `restore` riprende Flux e lo costringe a riapplicare lo stato di Git, che e' la correzione.
#
# Sicurezza: lavora solo sul contesto k3d-boutique e sul namespace boutique-dev.
set -euo pipefail

CTX="k3d-boutique"
NS="boutique-dev"
KS="boutique-dev"
K=(kubectl --context "$CTX" -n "$NS")

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

guard() {
  local ctx
  ctx="$(kubectl config current-context)"
  if [ "$ctx" != "$CTX" ]; then
    echo "Contesto kubectl '$ctx': questo script lavora solo su '$CTX'. Nessuna modifica." >&2
    exit 1
  fi
}

suspended() {
  kubectl --context "$CTX" -n flux-system get kustomization "$KS" \
    -o jsonpath='{.spec.suspend}' 2>/dev/null
}

# Sospende Flux; se il comando di guasto che segue fallisce, la riprende (niente sospensioni dimenticate).
suspend_flux() {
  flux --context "$CTX" suspend kustomization "$KS"
  trap 'echo "Guasto non applicato: riprendo Flux." >&2; flux --context "$CTX" resume kustomization "$KS"' ERR
}

stamp() { echo "[$(date +%H:%M:%S)] $*"; }

status() {
  s="$(suspended || true)"
  echo "Flux ($KS) sospesa: ${s:-false}"
  if [ "$s" = "true" ]; then
    echo "ATTENZIONE: Flux e' sospesa. Esegui 'scripts/break-it.sh restore' a fine prova."
  fi
  "${K[@]}" get pods --no-headers | awk '{split($2, r, "/"); if (r[1] != r[2] || $3 != "Running") print "  non sano: " $0}'
  "${K[@]}" get pods
}

restore() {
  stamp "riprendo Flux e riapplico lo stato di Git"
  flux --context "$CTX" resume kustomization "$KS"
  flux --context "$CTX" reconcile kustomization "$KS" --with-source
  # Git non dichiara `replicas` (solo loadgenerator): Flux non annulla uno scale a mano.
  "${K[@]}" scale deploy/frontend --replicas=1
  for d in frontend checkoutservice currencyservice; do
    "${K[@]}" rollout status "deploy/$d" --timeout=180s
  done
  # Verifica finale: ogni Deployment deve avere almeno una replica e tutte pronte.
  bad="$("${K[@]}" get deploy --no-headers | awk '{split($2, r, "/"); if (r[1] != r[2] || r[2] == 0) print $1}')"
  if [ -n "$bad" ]; then
    echo "ERRORE: ripristino incompleto, Deployment non pronti: $bad" >&2
    exit 1
  fi
  stamp "ripristino completato"
  status
}

[ $# -eq 1 ] || usage
scenario="$1"
guard

case "$scenario" in
  status) status ;;
  restore) restore ;;
  image-tag)
    suspend_flux
    stamp "GUASTO: frontend con tag inesistente"
    img="$("${K[@]}" get deploy frontend -o jsonpath='{.spec.template.spec.containers[0].image}')"
    "${K[@]}" set image deploy/frontend "server=${img%:*}:tag-che-non-esiste"
    echo "Atteso: nuovo pod in ImagePullBackOff; il vecchio resta in servizio (rolling update)."
    ;;
  bad-addr)
    suspend_flux
    stamp "GUASTO: frontend con PRODUCT_CATALOG_SERVICE_ADDR sbagliato"
    "${K[@]}" set env deploy/frontend PRODUCT_CATALOG_SERVICE_ADDR=productcatalogservice-sbagliato:3550
    echo "Atteso: pod Running e Ready, pagine in errore 500, alert FrontendHigh5xxRate."
    ;;
  missing-addr)
    suspend_flux
    stamp "GUASTO: checkoutservice senza SHIPPING_SERVICE_ADDR"
    "${K[@]}" set env deploy/checkoutservice SHIPPING_SERVICE_ADDR-
    echo "Atteso: nuovo pod in CrashLoopBackOff (panic all'avvio); il vecchio resta in servizio."
    ;;
  low-memory)
    suspend_flux
    stamp "GUASTO: currencyservice con limite di memoria 16Mi"
    "${K[@]}" set resources deploy/currencyservice --limits=memory=16Mi --requests=memory=16Mi
    echo "Atteso: pod riavviato con Reason OOMKilled (exit 137), poi CrashLoopBackOff."
    ;;
  frontend-down)
    suspend_flux
    stamp "GUASTO: frontend a 0 repliche"
    "${K[@]}" scale deploy/frontend --replicas=0
    echo "Atteso: shop irraggiungibile (503 dall'Ingress, 502 nei primi secondi), alert FrontendUnavailable."
    ;;
  *) usage ;;
esac
