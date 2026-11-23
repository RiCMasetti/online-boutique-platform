#!/usr/bin/env bash
# Utility operative per controllare cluster, pod, Flux, manifest e traffico di prova.
# Uso: scripts/ops.sh [-n dev|prod|<namespace>] <comando> [argomenti]
#
# Controllo cluster (sola lettura):
#   status                 nodi, pod del namespace, pod da guardare, riepilogo Flux
#   top [cpu|mem]          CPU e memoria di nodi e pod, con % rispetto ai limits
#   logs <svc|pod> [-f] [--since 10m] [--tail N] [-c container]
#   prev <svc|pod> [--tail N]   log del container precedente (dopo un restart)
#   why  <svc|pod>         stato, ultimo stop (OOMKilled, exit code), probe, risorse, eventi
#   restarts               container con restart > 0 e motivo dell'ultimo stop
#   events [--warnings] [--tail N]
#
# Flux:
#   flux [status]          sorgenti, Kustomization e HelmRelease: Ready, revisione, ritardo
#   flux events            ultimi eventi degli oggetti Flux
#   flux logs [controller] [--tail N] [--errors] [-f]   (default: kustomize-controller)
#   flux reconcile [kustomization] [--with-source]      (modifica: chiede una riconciliazione)
#
# Manifest:
#   build [dev|prod|infra|stack|config|all|<percorso>] [--out DIR]
#                          kustomize build + kubeconform, come la CI (docs/ci.md)
#
# Accesso e traffico:
#   grafana [--copy|--raw|--open]   URL e credenziali admin di Grafana (dal Secret nel cluster)
#   load status|up|down|set|stop|start|reset   traffico del loadgenerator (solo dev)
#
# Variabili: CONTEXT (default k3d-boutique), HOST_PORT (8080), GRAFANA_NS (monitoring),
#            LOAD_MAX_USERS (200), KUBE_VERSION per kubeconform (1.33.0, come la CI).
# Tutti i comandi leggono soltanto, tranne: flux reconcile, load (tranne status), grafana --open/--copy.
# Compatibile con bash 3.2 (macOS).
set -uo pipefail

CONTEXT="${CONTEXT:-k3d-boutique}"
HOST_PORT="${HOST_PORT:-8080}"
GRAFANA_NS="${GRAFANA_NS:-monitoring}"
LOAD_MAX_USERS="${LOAD_MAX_USERS:-200}"
KUBE_VERSION="${KUBE_VERSION:-1.33.0}"
NS="boutique-dev"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

KS_API="kustomizations.kustomize.toolkit.fluxcd.io"
HR_API="helmreleases.helm.toolkit.fluxcd.io"
GIT_API="gitrepositories.source.toolkit.fluxcd.io"
HELMREPO_API="helmrepositories.source.toolkit.fluxcd.io"

die() { echo "Errore: $*" >&2; exit 1; }
k() { kubectl --context "$CONTEXT" "$@"; }
need() { command -v "$1" >/dev/null 2>&1 || die "'$1' non trovato nel PATH"; }

usage() { sed -n '2,/^set -uo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

resolve_ns() {
  case "$1" in
    dev|prod) echo "boutique-$1" ;;
    *) echo "$1" ;;
  esac
}

# Nomi dei pod per un servizio (label app=, poi app.kubernetes.io/name=, poi .../instance=)
# oppure per nome esatto di pod. Uno per riga. Esce con 1 se non trova nulla.
pods_of() {
  local t="$1" sel out
  if k -n "$NS" get pod "$t" >/dev/null 2>&1; then echo "$t"; return 0; fi
  for sel in "app=$t" "app.kubernetes.io/name=$t" "app.kubernetes.io/instance=$t"; do
    out="$(k -n "$NS" get pods -l "$sel" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)"
    if [ -n "$out" ]; then echo "$out" | tr ' ' '\n'; return 0; fi
  done
  return 1
}

# ---------------------------------------------------------------- status

# Riepilogo Flux su poche righe: quanti oggetti Ready e quali no (usato da status e flux).
flux_summary() {
  local json
  json="$(k get "$KS_API,$HR_API" -A -o json 2>/dev/null)" || { echo "Flux non installato in $CONTEXT"; return; }
  echo "$json" | jq -r '
    [.items[] | {kind, name: .metadata.name, susp: (.spec.suspend // false),
        ready: (([.status.conditions[]? | select(.type == "Ready")][0].status) // "?"),
        msg: (([.status.conditions[]? | select(.type == "Ready")][0].message) // "" | gsub("\n"; " ") | .[:100])}] as $i
    | "\($i | length) oggetti, \([$i[] | select(.ready == "True" and (.susp | not))] | length) Ready",
      ($i[] | select(.ready != "True" or .susp) | "  \(.kind)/\(.name)\t\(if .susp then "SOSPESO" else "Ready=" + .ready end)\t\(.msg)")'
}

cmd_status() {
  echo "== Nodi =="
  k get nodes
  echo
  echo "== Pod in $NS =="
  k -n "$NS" get pods
  echo
  echo "== Da guardare in $NS =="
  local json out nrst
  json="$(k -n "$NS" get pods -o json)" || exit 1
  out="$(echo "$json" | jq -r '
    .items[] | select(.status.phase != "Succeeded") | . as $p
    | ([$p.status.containerStatuses[]? | select(.ready | not)] | length) as $nr
    | select($p.status.phase != "Running" or $nr > 0)
    | "\($p.metadata.name)\tfase=\($p.status.phase)\tcontainer-non-ready=\($nr)"')"
  if [ -z "$out" ]; then
    echo "tutti i pod sono Running e Ready"
  else
    echo "$out" | column -t -s $'\t'
    echo "(dettagli: ops.sh why <pod>)"
  fi
  nrst="$(echo "$json" | jq '[.items[] | select([.status.containerStatuses[]? | select(.restartCount > 0)] | length > 0)] | length')"
  if [ "$nrst" -gt 0 ]; then
    echo "$nrst pod con restart passati (vedi: ops.sh restarts, ops.sh prev <servizio>)"
  fi
  echo
  echo "== Flux =="
  flux_summary | column -t -s $'\t'
}

# ---------------------------------------------------------------- top

cmd_top() {
  local sort="${1:-mem}" pods metrics
  case "$sort" in cpu|mem) ;; *) die "uso: ops.sh top [cpu|mem]" ;; esac
  echo "== Nodi =="
  k top nodes || die "metrics-server non risponde"
  echo
  echo "== Pod in $NS (ordinati per $sort; % = uso / limit; i valori sono una fotografia) =="
  pods="$(k -n "$NS" get pods -o json)" || exit 1
  metrics="$(k get --raw "/apis/metrics.k8s.io/v1beta1/namespaces/$NS/pods")" || die "metriche dei pod non disponibili"
  jq -r -n --argjson pods "$pods" --argjson m "$metrics" --arg sort "$sort" '
    def cpu: if endswith("n") then (.[:-1] | tonumber) / 1e6
             elif endswith("u") then (.[:-1] | tonumber) / 1e3
             elif endswith("m") then (.[:-1] | tonumber)
             else (tonumber * 1000) end;
    def mem: capture("^(?<n>[0-9.]+)(?<u>[A-Za-z]*)$") as $c
             | ($c.n | tonumber)
               * ({"": 1, "Ki": 1024, "Mi": 1048576, "Gi": 1073741824, "K": 1000, "k": 1000, "M": 1000000, "G": 1000000000}[$c.u] // 1)
               / 1048576;
    def qcpu: if . == null then null else cpu end;
    def qmem: if . == null then null else mem end;
    # somma sui container; se uno non dichiara il valore, il totale non e affidabile: null
    def tot(f): [.spec.containers[] | f] | if any(. == null) then null else add end;
    def n: if . == null then "-" else (round | tostring) end;
    def pct(u; l): if l == null or l == 0 then null else (u / l * 100 | round) end;
    def ps: if . == null then "-" else "\(.)%" end;
    ($m.items | map({key: .metadata.name, value: .}) | from_entries) as $idx
    | [ $pods.items[] | select($idx[.metadata.name]) | $idx[.metadata.name] as $u
        | { pod: .metadata.name,
            cpu: ([$u.containers[].usage.cpu | cpu] | add),
            mem: ([$u.containers[].usage.memory | mem] | add),
            creq: tot(.resources.requests.cpu | qcpu), clim: tot(.resources.limits.cpu | qcpu),
            mreq: tot(.resources.requests.memory | qmem), mlim: tot(.resources.limits.memory | qmem) } ]
    | sort_by(if $sort == "cpu" then -.cpu else -.mem end) as $rows
    | (["POD", "CPU(m)", "REQ", "LIM", "CPU%", "MEM(Mi)", "REQ", "LIM", "MEM%", "NOTA"] | @tsv),
      ($rows[] | pct(.cpu; .clim) as $cp | pct(.mem; .mlim) as $mp
        | [.pod, (.cpu | n), (.creq | n), (.clim | n), ($cp | ps),
           (.mem | n), (.mreq | n), (.mlim | n), ($mp | ps),
           (if ($mp // 0) >= 80 then "mem>=80%" elif ($cp // 0) >= 80 then "cpu>=80%" else "-" end)]
        | @tsv)' | column -t -s $'\t'
}

# ---------------------------------------------------------------- logs, prev, why

cmd_logs() {
  local follow=0 since="" tail=100 container="" target="" pods p
  while [ $# -gt 0 ]; do
    case "$1" in
      -f|--follow) follow=1 ;;
      --since) [ $# -ge 2 ] || die "--since richiede un valore"; since="$2"; shift ;;
      --tail) [ $# -ge 2 ] || die "--tail richiede un valore"; tail="$2"; shift ;;
      -c|--container) [ $# -ge 2 ] || die "-c richiede un valore"; container="$2"; shift ;;
      -*) die "opzione sconosciuta: $1" ;;
      *) target="$1" ;;
    esac
    shift
  done
  [ -n "$target" ] || die "uso: ops.sh logs <servizio|pod> [-f] [--since 10m] [--tail N] [-c container]"
  pods="$(pods_of "$target")" || die "nessun pod per '$target' in $NS"
  local args=(--prefix --tail "$tail")
  if [ -n "$since" ]; then args+=(--since "$since"); fi
  if [ -n "$container" ]; then args+=(-c "$container"); else args+=(--all-containers); fi
  if [ "$follow" -eq 1 ]; then args+=(-f); fi
  for p in $pods; do
    if [ "$follow" -eq 1 ]; then
      k -n "$NS" logs "$p" "${args[@]}" &
    else
      k -n "$NS" logs "$p" "${args[@]}"
    fi
  done
  if [ "$follow" -eq 1 ]; then wait; fi
}

cmd_prev() {
  local target="" tail=100 pods p rows c n reason code when found=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --tail) [ $# -ge 2 ] || die "--tail richiede un valore"; tail="$2"; shift ;;
      -*) die "opzione sconosciuta: $1" ;;
      *) target="$1" ;;
    esac
    shift
  done
  [ -n "$target" ] || die "uso: ops.sh prev <servizio|pod> [--tail N]"
  pods="$(pods_of "$target")" || die "nessun pod per '$target' in $NS"
  for p in $pods; do
    rows="$(k -n "$NS" get pod "$p" -o json | jq -r '
      .status.containerStatuses[]? | select(.restartCount > 0)
      | [.name, (.restartCount | tostring), (.lastState.terminated.reason // "?"),
         ((.lastState.terminated.exitCode // "?") | tostring), (.lastState.terminated.finishedAt // "?")]
      | @tsv')"
    [ -n "$rows" ] || continue
    while IFS=$'\t' read -r c n reason code when; do
      found=1
      echo "=== $p / $c  (restart=$n, ultimo stop: $reason exit=$code alle $when) ==="
      k -n "$NS" logs "$p" -c "$c" --previous --tail "$tail" 2>&1 || echo "(log precedenti non disponibili)"
      echo
    done <<< "$rows"
  done
  if [ "$found" -eq 0 ]; then
    echo "Nessun container di '$target' in $NS è stato riavviato: non ci sono log precedenti."
  fi
}

cmd_why() {
  local target="${1:-}" pods p
  [ -n "$target" ] || die "uso: ops.sh why <servizio|pod>"
  pods="$(pods_of "$target")" || die "nessun pod per '$target' in $NS"
  for p in $pods; do
    k -n "$NS" get pod "$p" -o json | jq -r '
      def pr: if . == null then "-"
              else (if .grpc then "grpc:\(.grpc.port)" elif .httpGet then "http:\(.httpGet.path)"
                    elif .tcpSocket then "tcp:\(.tcpSocket.port)" elif .exec then "exec" else "?" end)
                   + " t=\(.timeoutSeconds // 1)s" end;
      "== POD \(.metadata.name)  fase=\(.status.phase)  nodo=\(.spec.nodeName // "-")  avvio=\(.status.startTime // "-")",
      (.status.conditions[]? | select(.status != "True") | "  condizione \(.type)=\(.status) \(.reason // "") \(.message // "")"),
      (.spec.containers as $specs
       | .status.containerStatuses[]? as $s
       | ($specs[] | select(.name == $s.name)) as $c
       | "  container \($s.name): ready=\($s.ready) restart=\($s.restartCount) stato=\($s.state | keys[0])"
         + (if $s.state.waiting then " (\($s.state.waiting.reason // "?"))" else "" end),
         (if $s.lastState.terminated
          then "    ultimo stop: \($s.lastState.terminated.reason // "?") exit=\($s.lastState.terminated.exitCode) alle \($s.lastState.terminated.finishedAt)"
          else empty end),
         "    risorse: cpu req=\($c.resources.requests.cpu // "-") lim=\($c.resources.limits.cpu // "-"), mem req=\($c.resources.requests.memory // "-") lim=\($c.resources.limits.memory // "-")",
         "    probe: liveness=\($c.livenessProbe | pr)  readiness=\($c.readinessProbe | pr)")'
    echo "  -- ultimi eventi --"
    k -n "$NS" get events --field-selector "involvedObject.name=$p" --sort-by=.lastTimestamp 2>&1 | tail -n 9 | sed 's/^/  /'
    echo
  done
}

cmd_restarts() {
  local out
  out="$(k -n "$NS" get pods -o json | jq -r '
    .items[] | .metadata.name as $p
    | .status.containerStatuses[]? | select(.restartCount > 0)
    | [$p, .name, (.restartCount | tostring), (.lastState.terminated.reason // "?"),
       ((.lastState.terminated.exitCode // "?") | tostring), (.lastState.terminated.finishedAt // "?")]
    | @tsv')"
  if [ -z "$out" ]; then
    echo "Nessun container con restart in $NS."
  else
    { printf 'POD\tCONTAINER\tRESTART\tMOTIVO\tEXIT\tQUANDO\n'; echo "$out"; } | column -t -s $'\t'
  fi
}

cmd_events() {
  local warnings=0 tail=30
  while [ $# -gt 0 ]; do
    case "$1" in
      --warnings) warnings=1 ;;
      --tail) [ $# -ge 2 ] || die "--tail richiede un valore"; tail="$2"; shift ;;
      *) die "opzione sconosciuta: $1" ;;
    esac
    shift
  done
  if [ "$warnings" -eq 1 ]; then
    k -n "$NS" get events --sort-by=.lastTimestamp --field-selector type=Warning 2>&1 | tail -n "$tail"
  else
    k -n "$NS" get events --sort-by=.lastTimestamp 2>&1 | tail -n "$tail"
  fi
}

# ---------------------------------------------------------------- flux

# Chiede la riconciliazione di una Kustomization e attende che Flux l'abbia gestita.
# ks_reconcile <nome> [con-sorgente: 0|1]
ks_reconcile() {
  local name="$1" with_source="${2:-0}" token i handled src_kind src_name
  token="$(date +%s)"
  if [ "$with_source" = "1" ]; then
    src_kind="$(k -n flux-system get "$KS_API" "$name" -o jsonpath='{.spec.sourceRef.kind}')"
    src_name="$(k -n flux-system get "$KS_API" "$name" -o jsonpath='{.spec.sourceRef.name}')"
    if [ "$src_kind" = "GitRepository" ]; then
      k -n flux-system annotate "$GIT_API" "$src_name" "reconcile.fluxcd.io/requestedAt=$token" --overwrite >/dev/null
      for i in $(seq 1 30); do
        handled="$(k -n flux-system get "$GIT_API" "$src_name" -o jsonpath='{.status.lastHandledReconcileAt}')"
        [ "$handled" = "$token" ] && break
        sleep 2
      done
    fi
  fi
  k -n flux-system annotate "$KS_API" "$name" "reconcile.fluxcd.io/requestedAt=$token" --overwrite >/dev/null || return 1
  for i in $(seq 1 60); do
    handled="$(k -n flux-system get "$KS_API" "$name" -o jsonpath='{.status.lastHandledReconcileAt}')"
    [ "$handled" = "$token" ] && return 0
    sleep 2
  done
  echo "Attenzione: Flux non ha confermato la riconciliazione di $name entro 120 s." >&2
  return 1
}

flux_status() {
  local src ks hr
  src="$(k get "$GIT_API,$HELMREPO_API" -A -o json 2>/dev/null)" || die "CRD di Flux non trovate in $CONTEXT: Flux non è installato"
  ks="$(k get "$KS_API" -A -o json)" || exit 1
  hr="$(k get "$HR_API" -A -o json 2>/dev/null || echo '{"items":[]}')"
  jq -r -n --argjson src "$src" --argjson ks "$ks" --argjson hr "$hr" '
    def short: if . == null then "-" else gsub("(?<p>sha[0-9]+:)(?<s>[0-9a-f]{8})[0-9a-f]+"; "\(.p)\(.s)") end;
    def rdy: ([.status.conditions[]? | select(.type == "Ready")][0]) as $c
             | if $c == null then {s: "?", m: ""} else {s: $c.status, m: (($c.message // "") | gsub("\n"; " ") | .[:80])} end;
    ($src.items | map({key: "\(.kind)/\(.metadata.namespace)/\(.metadata.name)", value: .status.artifact.revision}) | from_entries) as $rev
    | "== Sorgenti ==",
    (["TIPO", "NOME", "READY", "REVISIONE", "NOTA"] | @tsv),
    ($src.items[] | rdy as $r
      | [.kind, .metadata.name, $r.s, (.status.artifact.revision | short), (if $r.s == "True" then "-" else $r.m end)] | @tsv),
    "",
    "== Kustomization ==",
    (["NOME", "PERCORSO", "READY", "SOSPESA", "APPLICATA", "NOTA"] | @tsv),
    ($ks.items[] | rdy as $r
      | $rev["\(.spec.sourceRef.kind)/\(.spec.sourceRef.namespace // .metadata.namespace)/\(.spec.sourceRef.name)"] as $want
      | [.metadata.name, .spec.path, $r.s, ((.spec.suspend // false) | tostring), (.status.lastAppliedRevision | short),
         (if (.spec.suspend // false) then "SOSPESA: Flux non riallinea questo percorso"
          elif $r.s != "True" then $r.m
          elif $want != null and $want != .status.lastAppliedRevision then "in ritardo: la sorgente è a \($want | short)"
          else "-" end)] | @tsv),
    "",
    "== HelmRelease ==",
    (["NS/NOME", "READY", "SOSPESA", "CHART", "NOTA"] | @tsv),
    ($hr.items[] | rdy as $r
      | ["\(.metadata.namespace)/\(.metadata.name)", $r.s, ((.spec.suspend // false) | tostring),
         (.status.history[0].chartVersion // "-"), (if $r.s == "True" then "-" else $r.m end)] | @tsv)' \
    | awk -F'\t' '
        /^==/ { if (buf != "") { print buf | "column -t -s \"\t\""; close("column -t -s \"\t\"") } buf = ""; print; next }
        /^$/  { if (buf != "") { print buf | "column -t -s \"\t\""; close("column -t -s \"\t\"") } buf = ""; print; next }
        { buf = (buf == "" ? $0 : buf "\n" $0) }
        END { if (buf != "") { print buf | "column -t -s \"\t\""; close("column -t -s \"\t\"") } }'
}

flux_events() {
  k get events -A -o json | jq -r '
    [.items[] | select(.involvedObject.kind as $k | ["Kustomization", "HelmRelease", "GitRepository", "HelmRepository"] | index($k))
     | {t: (.lastTimestamp // .eventTime // .metadata.creationTimestamp), type, reason,
        obj: "\(.involvedObject.kind)/\(.involvedObject.name)", msg: ((.message // "") | gsub("\n"; " ") | .[:120])}]
    | sort_by(.t) | .[-20:][]
    | [.t, .type, .reason, .obj, .msg] | @tsv' | column -t -s $'\t'
}

flux_logs() {
  local controller="kustomize-controller" tail=100 errors=0 follow=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --tail) [ $# -ge 2 ] || die "--tail richiede un valore"; tail="$2"; shift ;;
      --errors) errors=1 ;;
      -f|--follow) follow=1 ;;
      -*) die "opzione sconosciuta: $1" ;;
      *) controller="$1" ;;
    esac
    shift
  done
  case "$controller" in
    source|helm|kustomize|notification) controller="$controller-controller" ;;
  esac
  local args=(--tail "$tail")
  if [ "$follow" -eq 1 ]; then args+=(-f); fi
  if [ "$errors" -eq 1 ]; then
    k -n flux-system logs "deploy/$controller" "${args[@]}" | grep -E '"level":"(error|warn|warning)"' || echo "(nessun log error/warn nelle ultime $tail righe di $controller)"
  else
    k -n flux-system logs "deploy/$controller" "${args[@]}"
  fi
}

cmd_flux() {
  local sub="${1:-status}"
  if [ $# -gt 0 ]; then shift; fi
  case "$sub" in
    status) flux_status ;;
    events) flux_events ;;
    logs) flux_logs "$@" ;;
    reconcile)
      local name="" with_source=0 a
      for a in "$@"; do
        case "$a" in
          --with-source) with_source=1 ;;
          -*) die "opzione sconosciuta: $a" ;;
          *) name="$a" ;;
        esac
      done
      name="${name:-$NS}"
      k -n flux-system get "$KS_API" "$name" >/dev/null 2>&1 || die "Kustomization '$name' non trovata (nomi: $(k -n flux-system get "$KS_API" -o jsonpath='{.items[*].metadata.name}'))"
      echo "Riconciliazione di $name..."
      ks_reconcile "$name" "$with_source" && echo "Fatto." || exit 1
      flux_status | sed -n '/== Kustomization/,/^$/p'
      ;;
    *) die "uso: ops.sh flux [status|events|logs|reconcile]" ;;
  esac
}

# ---------------------------------------------------------------- build

# build_target <nome> <percorso> <ignora-schemi-mancanti: 0|1> <cartella-uscita|"">
build_target() {
  local name="$1" path="$2" ignore="$3" outdir="$4" f errf res rc flags
  local full="$path"
  case "$path" in /*) ;; *) full="$ROOT/$path" ;; esac
  f="$BUILD_TMP/$name.yaml"
  errf="$BUILD_TMP/$name.err"
  if ! kustomize build "$full" >"$f" 2>"$errf"; then
    echo "FAIL  $name ($path): kustomize build"
    head -n 20 "$errf" | sed 's/^/        /'
    return 1
  fi
  if [ ! -s "$f" ]; then
    echo "FAIL  $name ($path): il build non produce nessuna risorsa (è un component? va costruito da un overlay)"
    return 1
  fi
  # -skip Secret: il Secret SOPS ha la chiave "sops" alla radice, che lo schema non ammette
  # (Flux la toglie decifrando). Stessi flag della CI (.github/workflows/checks.yaml).
  flags=(-strict -skip Secret -summary -kubernetes-version "$KUBE_VERSION")
  if [ "$ignore" = "1" ]; then flags+=(-ignore-missing-schemas); fi
  res="$(kubeconform "${flags[@]}" "$f" 2>&1)"; rc=$?
  if [ -n "$outdir" ]; then mkdir -p "$outdir" && cp "$f" "$outdir/$name.yaml"; fi
  if [ "$rc" -eq 0 ]; then
    echo "OK    $name ($path): build riuscito. $(echo "$res" | tail -n 1)"
    return 0
  fi
  echo "FAIL  $name ($path): kubeconform"
  echo "$res" | head -n 30 | sed 's/^/        /'
  return 1
}

cmd_build() {
  need kustomize; need kubeconform
  local sel="all" outdir="" fail=0 t full
  while [ $# -gt 0 ]; do
    case "$1" in
      --out) [ $# -ge 2 ] || die "--out richiede una cartella"; outdir="$2"; shift ;;
      -*) die "opzione sconosciuta: $1" ;;
      *) sel="$1" ;;
    esac
    shift
  done
  BUILD_TMP="$(mktemp -d)"
  trap 'rm -rf "$BUILD_TMP"' EXIT
  echo "kustomize $(kustomize version 2>/dev/null | head -n 1), kubeconform $(kubeconform -v 2>/dev/null), schemi Kubernetes $KUBE_VERSION"
  case "$sel" in
    dev)    build_target dev deploy/overlays/dev 0 "$outdir" || fail=1 ;;
    prod)   build_target prod deploy/overlays/prod 0 "$outdir" || fail=1 ;;
    infra)  build_target infra infrastructure 1 "$outdir" || fail=1 ;;
    stack)  build_target obs-stack observability/stack 1 "$outdir" || fail=1 ;;
    config) build_target obs-config observability/config 1 "$outdir" || fail=1 ;;
    all)
      # Gli stessi percorsi che Flux applica (v. `ops.sh flux`), più le due da CI.
      # CRD (HelmRelease, ServiceMonitor, PrometheusRule) non hanno schema: -ignore-missing-schemas.
      build_target dev deploy/overlays/dev 0 "$outdir" || fail=1
      build_target prod deploy/overlays/prod 0 "$outdir" || fail=1
      build_target infra infrastructure 1 "$outdir" || fail=1
      build_target obs-stack observability/stack 1 "$outdir" || fail=1
      build_target obs-config observability/config 1 "$outdir" || fail=1
      ;;
    *)
      t="${sel#"$ROOT"/}"
      case "$t" in /*) full="$t" ;; *) full="$ROOT/$t" ;; esac
      [ -f "$full/kustomization.yaml" ] || die "'$sel' non è dev|prod|infra|stack|config|all né una cartella con kustomization.yaml (relativa alla radice del repo)"
      build_target "$(basename "$t")" "$t" 1 "$outdir" || fail=1
      ;;
  esac
  if [ "$fail" -ne 0 ]; then echo; echo "Almeno un build è fallito."; exit 1; fi
}

# ---------------------------------------------------------------- grafana

cmd_grafana() {
  local copy=0 raw=0 open=0 a user pass host url code secret
  for a in "$@"; do
    case "$a" in
      --copy) copy=1 ;;
      --raw) raw=1 ;;
      --open) open=1 ;;
      *) die "opzione sconosciuta: $a (uso: grafana [--copy|--raw|--open])" ;;
    esac
  done
  secret="$(k -n "$GRAFANA_NS" get secret grafana-admin -o json 2>/dev/null)" \
    || die "Secret grafana-admin non trovato in $GRAFANA_NS"
  user="$(echo "$secret" | jq -r '.data["admin-user"] | @base64d')"
  pass="$(echo "$secret" | jq -r '.data["admin-password"] | @base64d')"
  if [ "$raw" -eq 1 ]; then printf '%s\n' "$pass"; return 0; fi
  host="$(k -n "$GRAFANA_NS" get ingress -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null)"
  url="http://${host:-grafana.localtest.me}:${HOST_PORT}"
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url/api/health" || true)"
  echo "URL:       $url   (health: HTTP ${code:-000})"
  echo "utente:    $user"
  if [ "$copy" -eq 1 ]; then
    need pbcopy
    printf '%s' "$pass" | pbcopy
    echo "password:  copiata negli appunti"
  else
    echo "password:  $pass"
  fi
  if [ "${code:-000}" != "200" ]; then
    echo "Grafana non risponde dall'Ingress. Alternativa: kubectl --context $CONTEXT -n $GRAFANA_NS port-forward svc/kube-prometheus-stack-grafana 3000:80"
  fi
  if [ "$open" -eq 1 ]; then need open; open "$url"; fi
}

# ---------------------------------------------------------------- load

need_loadgen() {
  k -n "$NS" get deploy loadgenerator >/dev/null 2>&1 \
    || die "nessun loadgenerator in $NS (è attivo solo in dev: usa -n dev)"
}

# Stampa "USERS RATE REPLICAS" correnti (default dell'immagine: 10 e 1).
load_get() {
  k -n "$NS" get deploy loadgenerator -o json | jq -r '
    (.spec.template.spec.containers[] | select(.name == "main") | .env // []) as $e
    | [($e | map(select(.name == "USERS"))[0].value // "10"),
       ($e | map(select(.name == "RATE"))[0].value // "1"),
       (.spec.replicas | tostring)] | join(" ")'
}

flux_manages() { k -n flux-system get "$KS_API" "$NS" >/dev/null 2>&1; }
flux_suspended() { [ "$(k -n flux-system get "$KS_API" "$NS" -o jsonpath='{.spec.suspend}' 2>/dev/null)" = "true" ]; }

# Dopo una modifica manuale: o si sospende Flux (--hold) o si avverte che la ripristinerà.
after_change() {
  local hold="$1" interval
  flux_manages || return 0
  if [ "$hold" -eq 1 ]; then
    k -n flux-system patch "$KS_API" "$NS" --type merge -p '{"spec":{"suspend":true}}' >/dev/null
    echo "Flux sospeso su $NS: la modifica resta finché non lanci 'ops.sh load reset'."
  elif flux_suspended; then
    echo "Flux è già sospeso su $NS: la modifica resta finché non lanci 'ops.sh load reset'."
  else
    interval="$(k -n flux-system get "$KS_API" "$NS" -o jsonpath='{.spec.interval}')"
    echo "Nota: Flux riporta il Deployment allo stato di Git entro ${interval} (drift correction)."
    echo "      Per tenerla: aggiungi --hold. Per tornare a Git subito: ops.sh load reset."
  fi
}

load_status() {
  local u r n
  read -r u r n <<< "$(load_get)"
  echo "loadgenerator in $NS: repliche=$n  USERS=$u  RATE=$r utenti/s"
  if flux_manages; then
    if flux_suspended; then
      echo "Flux ($NS): SOSPESO. Le modifiche manuali restano; 'ops.sh load reset' ripristina Git."
    else
      echo "Flux ($NS): attivo, ripristina Git a ogni riconciliazione."
    fi
  fi
  k -n "$NS" get pods -l app=loadgenerator
  if [ "$n" != "0" ]; then
    echo "-- ultime statistiche Locust (richieste totali, errori, ms mediani, richieste/s) --"
    k -n "$NS" logs deploy/loadgenerator --tail 30 2>/dev/null \
      | awk '/Aggregated/ {l=$0} END {if (l != "") print l; else print "(ancora nessuna statistica)"}'
  fi
}

load_apply_users() {
  local users="$1" rate="$2" force="$3" hold="$4" cu cr cn
  [[ "$users" =~ ^[1-9][0-9]*$ ]] || die "USERS deve essere un intero >= 1 (ricevuto: '$users')"
  [[ "$rate" =~ ^[1-9][0-9]*$ ]] || die "RATE deve essere un intero >= 1 (ricevuto: '$rate')"
  if [ "$users" -gt "$LOAD_MAX_USERS" ] && [ "$force" -ne 1 ]; then
    die "USERS=$users supera il tetto di sicurezza $LOAD_MAX_USERS (il nodo k3d è piccolo). Usa --force o LOAD_MAX_USERS."
  fi
  read -r cu cr cn <<< "$(load_get)"
  k -n "$NS" set env deploy/loadgenerator "USERS=$users" "RATE=$rate" >/dev/null || exit 1
  echo "USERS $cu -> $users, RATE $cr -> $rate (il pod viene ricreato)"
  k -n "$NS" rollout status deploy/loadgenerator --timeout=180s || exit 1
  after_change "$hold"
}

load_set() {
  local users="$1" rate="$2" force="$3" hold="$4" cu cr cn
  [ -n "$users" ] || die "uso: ops.sh load set <utenti> [rate] [--force] [--hold]"
  read -r cu cr cn <<< "$(load_get)"
  load_apply_users "$users" "${rate:-$cr}" "$force" "$hold"
}

# up/down <fattore>: moltiplica o divide USERS e RATE (minimo 1).
load_scale() {
  local dir="$1" factor="$2" force="$3" hold="$4" cu cr cn nu nr
  [[ "$factor" =~ ^[2-9]$|^[1-9][0-9]+$ ]] || die "il fattore deve essere un intero >= 2 (ricevuto: '$factor')"
  read -r cu cr cn <<< "$(load_get)"
  [ "$cn" != "0" ] || die "il loadgenerator è fermo (repliche=0): usa 'ops.sh load start'"
  if [ "$dir" = "up" ]; then
    nu=$((cu * factor)); nr=$((cr * factor))
  else
    nu=$((cu / factor)); nr=$((cr / factor))
    [ "$nu" -ge 1 ] || nu=1
    [ "$nr" -ge 1 ] || nr=1
  fi
  load_apply_users "$nu" "$nr" "$force" "$hold"
}

load_replicas() {
  local n="$1" hold="$2"
  k -n "$NS" scale deploy/loadgenerator --replicas="$n" >/dev/null || exit 1
  if [ "$n" -gt 0 ]; then k -n "$NS" rollout status deploy/loadgenerator --timeout=180s || exit 1; fi
  echo "loadgenerator: repliche=$n"
  after_change "$hold"
}

load_reset() {
  flux_manages || die "Flux non gestisce $NS: niente da ripristinare (rilancia scripts/apply-local.sh se serve)"
  k -n flux-system patch "$KS_API" "$NS" --type merge -p '{"spec":{"suspend":false}}' >/dev/null
  echo "Flux riattivato su $NS, riconcilio dallo stato di Git..."
  ks_reconcile "$NS" 0 || exit 1
  k -n "$NS" rollout status deploy/loadgenerator --timeout=180s || true
  load_status
}

cmd_load() {
  local sub="${1:-status}" hold=0 force=0 a
  if [ $# -gt 0 ]; then shift; fi
  local pos=()
  for a in "$@"; do
    case "$a" in
      --hold) hold=1 ;;
      --force) force=1 ;;
      -*) die "opzione sconosciuta: $a" ;;
      *) pos+=("$a") ;;
    esac
  done
  need_loadgen
  case "$sub" in
    status) load_status ;;
    set) load_set "${pos[0]:-}" "${pos[1]:-}" "$force" "$hold" ;;
    up|down) load_scale "$sub" "${pos[0]:-2}" "$force" "$hold" ;;
    stop) load_replicas 0 "$hold" ;;
    start) load_replicas 1 "$hold" ;;
    reset) load_reset ;;
    *) die "uso: ops.sh load status|up|down|set|stop|start|reset  (up/down [fattore], set <utenti> [rate], --hold, --force)" ;;
  esac
}

# ---------------------------------------------------------------- main

main() {
  need kubectl; need jq
  while [ $# -gt 0 ]; do
    case "$1" in
      -n|--namespace) [ $# -ge 2 ] || die "-n richiede un valore"; NS="$(resolve_ns "$2")"; shift 2 ;;
      -h|--help|help) usage; exit 0 ;;
      *) break ;;
    esac
  done
  local cmd="${1:-}"
  if [ $# -gt 0 ]; then shift; fi
  case "$cmd" in
    status|top|logs|prev|why|events|restarts|grafana|load|flux|build) "cmd_$cmd" "$@" ;;
    "") usage; exit 1 ;;
    *) die "comando sconosciuto: $cmd (vedi: ops.sh help)" ;;
  esac
}

main "$@"
