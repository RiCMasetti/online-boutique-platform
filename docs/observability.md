# Osservabilità

Stato a fine fase 5: il frontend espone metriche Prometheus. Prometheus, Grafana e gli alert arrivano in fase 7; `redis_exporter` e il resto della fase 5 non sono ancora fatti (vedi §5).

## 1. Metriche del frontend

Upstream il frontend non espone metriche. La modifica (`src/frontend/metrics.go` e 3 righe in `main.go`) aggiunge `/metrics` sulla stessa porta dell'app (8080) e due serie:

| Metrica | Tipo | Etichette |
|---|---|---|
| `frontend_http_requests_total` | counter | `method`, `route`, `code` |
| `frontend_http_request_duration_seconds` | histogram | `method`, `route` |

Più le metriche standard di Go e del processo (`go_*`, `process_*`).

Scelte e limiti:

- **`route` è il template** (`/product/{id}`), non l'URL reale, per tenere bassa la cardinalità. Lo ricava il middleware di `mux` dopo il routing.
- **Non sono contate** le richieste senza route (404: un contatore per URL arbitrario sarebbe un rischio di cardinalità) e `/_healthz` (le probe dominerebbero il traffico). Conseguenza: un 404 non compare in `frontend_http_requests_total`, e la disponibilità del frontend va misurata con `up` o con un probe esterno, non con questa metrica.
- **`/metrics` è servito prima degli altri middleware**: la scrape non crea cookie di sessione, log di richiesta né span di tracing.
- **`/metrics` è raggiungibile anche dall'Ingress**, perché Traefik inoltra ogni percorso al frontend. Espone solo contatori e dati di runtime, ma in un ambiente reale va chiuso (regola di Ingress o porta separata). Non fatto.
- **Per la fase 7:** la NetworkPolicy del frontend ammette in ingresso solo Traefik e loadgenerator sulla 8080 (`deploy/components/network-policies`): Prometheus, nel namespace `monitoring`, sarà bloccato finché non si aggiunge una regola.

Dipendenza: `github.com/prometheus/client_golang v1.23.2`. Le versioni più recenti (1.25) richiedono Go 1.26 e aggiornano altre dipendenze (`x/net`, `x/crypto`, ...); si è scelta la più recente compatibile senza toccare il resto di `go.mod`.

## 2. Immagine del frontend

Il Dockerfile resta quello upstream (multi-stage, `golang:alpine` poi `distroless`), con tre modifiche, tutte commentate nel file:

1. **Rimossi i default `BUILDPLATFORM`, `TARGETOS`, `TARGETARCH`.** Con i default l'immagine "arm64" conteneva un binario amd64 (vedi ADR 0002). Serve BuildKit (`docker buildx build`), che li valorizza.
2. **Immagine finale `distroless/static:nonroot` con digest**: riproducibile e utente 65532 di default (`hadolint` DL3006 risolto).
3. **`COPY --chmod=a=rX`** per `templates/` e `static/`: senza, l'immagine eredita i modi dell'host. Il repo su volume esterno (RicDisk) ha modo `0700` e l'utente non-root non poteva leggere i template (`panic: open templates/ad.html: permission denied`).

```bash
cd src/frontend
docker buildx build --platform linux/arm64 -t boutique/frontend:phase5 --load .
```

Variabili d'ambiente: tutte obbligatorie `*_SERVICE_ADDR` (`PRODUCT_CATALOG`, `CURRENCY`, `CART`, `RECOMMENDATION`, `CHECKOUT`, `SHIPPING`, `AD`, `SHOPPING_ASSISTANT`); facoltative `PORT` (default 8080), `LISTEN_ADDR`, `BASE_URL`, `ENABLE_TRACING`, `ENABLE_PROFILER`, `ENABLE_SINGLE_SHARED_SESSION`. I client gRPC sono lazy: per provare solo l'HTTP bastano indirizzi finti.

```bash
docker run --rm -p 8080:8080 --read-only --user 1000:1000 --cap-drop ALL \
  -e PRODUCT_CATALOG_SERVICE_ADDR=x:1 -e CURRENCY_SERVICE_ADDR=x:1 -e CART_SERVICE_ADDR=x:1 \
  -e RECOMMENDATION_SERVICE_ADDR=x:1 -e CHECKOUT_SERVICE_ADDR=x:1 -e SHIPPING_SERVICE_ADDR=x:1 \
  -e AD_SERVICE_ADDR=x:1 -e SHOPPING_ASSISTANT_SERVICE_ADDR=x:1 boutique/frontend:phase5
curl localhost:8080/metrics
```

## 3. Cosa è stato provato

| Prova | Esito |
|---|---|
| `go test ./...` (3 test nuovi in `metrics_test.go`: route template, `/_healthz` esclusa, `/metrics` senza cookie) | passati |
| `hadolint src/frontend/Dockerfile` | pulito |
| Build `linux/arm64` e `linux/amd64`; `file` sul binario estratto | `ARM aarch64` e `x86-64`, diversi (prima erano identici) |
| `docker run` con `--read-only --user 1000:1000 --cap-drop ALL` (come il pod) | parte; `/_healthz` 200 |
| Richieste a `/`, `/product/ABC`, `/robots.txt`, `/static/...`, URL inesistente | serie con `route` a template; 500 contati (backend finti); 404 non contata |
| `kubectl kustomize` su dev e prod | dev usa l'immagine locale, prod invariato; 51 risorse valide con `kubeconform` |

| Push su `main` → Flux applica `7d27ffc9` a dev; rollout del frontend con `boutique/frontend:phase5` | pod `1/1 Running`, shop 200 dall'Ingress |
| `/metrics` via `kubectl port-forward` dopo circa 20 s di loadgenerator | serie per `/product/{id}`, `/cart`, `/`, `/setCurrency`, `/cart/checkout`, nessun 5xx |
| Log del frontend in k3d (`kubectl logs`) | JSON (logrus), come da analisi di fase 1 |

**Non provato:** Prometheus che raccoglie la metrica (fase 7: il port-forward aggira la NetworkPolicy, quindi non dimostra che la scrape funzioni); la build `amd64` eseguita (solo ispezionato il binario, la macchina è arm64); `go vet` (segnala 72 avvisi `copylocks` già presenti in `money/` e `handlers.go`, nessuno nei file nuovi).

## 4. Immagine nel cluster, in attesa di GHCR

Fino alla fase 6 non c'è un registry: l'immagine si importa con `k3d image import boutique/frontend:phase5 -c boutique` e l'overlay dev la referenzia (`images:` in `deploy/overlays/dev/kustomization.yaml`). Il tag non è `latest`, quindi il pull policy è `IfNotPresent` e kubelet usa l'immagine importata. **Limite:** funziona solo su questo cluster e se l'immagine è stata importata; su un cluster nuovo il pod va in `ErrImagePull` finché non si rifà l'import. Prod resta sull'immagine upstream.

## 5. Ancora da fare in fase 5

`redis_exporter`; verifica dei log JSON a runtime (`kubectl logs`); controllo delle probe; build multi-arch degli altri servizi (fase 6).
