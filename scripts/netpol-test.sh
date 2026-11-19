#!/usr/bin/env bash
# Verifica che le NetworkPolicy siano applicate davvero da k3s.
# Lancia pod usa-e-getta con la label di un servizio e prova a connettersi ad altri servizi:
# alcune connessioni devono riuscire (percorsi previsti), altre devono essere bloccate.
# Uso: scripts/netpol-test.sh [namespace]   (default: boutique-dev)
# Nota: ogni pod di test è coperto dal deny-all, quindi si usano label di servizi la cui
# policy permette l'uscita (frontend, loadgenerator, cartservice): così un fallimento
# dipende dall'INGRESS del bersaglio e non dall'uscita del pod di test.
set -uo pipefail

NS="${1:-boutique-dev}"
CONTEXT="${CONTEXT:-k3d-boutique}"
IMAGE="busybox:1.38.0@sha256:dc2d74b28e4cf8984fa52af1f39bc7c3d9c73760b41a74d629f5d11b1ab28616"
fail=0

# probe <namespace-sorgente> <label app> <host> <porta> <allowed|blocked>
probe() {
  local src_ns="$1" label="$2" host="$3" port="$4" expect="$5" out result name overrides
  name="np-test-$RANDOM"
  # I namespace applicano Pod Security "restricted": il pod di test deve rispettarlo.
  # --overrides sostituisce l'intero container: immagine e comando vanno dichiarati qui.
  overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"'"$name"'","image":"'"$IMAGE"'","command":["sh","-c","nc -z -w 3 '"$host $port"'; echo rc=$?"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
  # Il pod stampa l'esito di nc ("rc=N"). Senza quella riga il pod non è partito o non ha
  # eseguito il test: è un ERRORE, non un "blocked" (altrimenti un pod non creato
  # farebbe risultare bloccata qualunque connessione).
  # Niente `run --rm -i`: il container finisce prima dell'attach e l'output andrebbe perso.
  # Si crea il pod, si attende il termine, si leggono i log e si elimina.
  out="$(kubectl --context "$CONTEXT" -n "$src_ns" run "$name" --restart=Never \
        --image="$IMAGE" --labels="app=$label" --overrides="$overrides" 2>&1 \
      && kubectl --context "$CONTEXT" -n "$src_ns" wait pod "$name" \
        --for=jsonpath='{.status.phase}'=Succeeded --timeout=90s 2>&1 \
      && kubectl --context "$CONTEXT" -n "$src_ns" logs "$name" 2>&1)"
  kubectl --context "$CONTEXT" -n "$src_ns" delete pod "$name" --wait=false >/dev/null 2>&1
  case "$out" in
    *rc=0*) result=allowed ;;
    *rc=[1-9]*) result=blocked ;;
    *) echo "ERRORE da app=$label ($src_ns) a $host:$port: il pod di test non ha prodotto un esito"
       echo "      output: $(echo "$out" | tail -1)"; fail=1; return ;;
  esac
  if [ "$result" = "$expect" ]; then
    echo "OK    da app=$label ($src_ns) a $host:$port: $result"
  else
    echo "FAIL  da app=$label ($src_ns) a $host:$port: atteso $expect, ottenuto $result"
    [ -n "$out" ] && echo "      output: $(echo "$out" | tail -1)"
    fail=1
  fi
}

# Percorsi previsti dal grafo (docs/architecture.md §3)
probe "$NS" frontend    "cartservice.$NS"   7070 allowed
probe "$NS" cartservice "redis-cart.$NS"    6379 allowed
# Il loadgenerator esiste solo in dev (in prod la sua policy è rimossa: il pod di test
# erediterebbe solo il deny-all e non potrebbe uscire).
if kubectl --context "$CONTEXT" -n "$NS" get networkpolicy loadgenerator >/dev/null 2>&1; then
  probe "$NS" loadgenerator "frontend.$NS" 80 allowed
fi
# Percorsi NON previsti: devono essere bloccati. Sorgente "emailservice": la sua policy
# permette l'uscita, e non è un chiamante di cartservice, Redis, frontend o payment.
probe "$NS" emailservice "cartservice.$NS"    7070  blocked
probe "$NS" emailservice "redis-cart.$NS"     6379  blocked
probe "$NS" emailservice "frontend.$NS"       80    blocked
probe "$NS" frontend     "redis-cart.$NS"     6379  blocked
probe "$NS" cartservice  "frontend.$NS"       80    blocked
probe "$NS" frontend     "paymentservice.$NS" 50051 blocked

# Isolamento tra ambienti (se l'altro namespace esiste): un pod "frontend" dell'altro
# ambiente non deve raggiungere il cartservice di questo.
OTHER="boutique-prod"; [ "$NS" = "boutique-prod" ] && OTHER="boutique-dev"
if kubectl --context "$CONTEXT" get ns "$OTHER" >/dev/null 2>&1; then
  probe "$OTHER" frontend "cartservice.$NS" 7070 blocked
fi

if [ $fail -eq 0 ]; then echo "NetworkPolicy verificate."; else echo "Verifica NetworkPolicy FALLITA." >&2; exit 1; fi
