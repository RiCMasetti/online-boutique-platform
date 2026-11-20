# Osservabilità

Stato a fine fase 5: il frontend espone metriche Prometheus. Prometheus, Grafana e gli alert arrivano in fase 7. Il resto della fase 5 è elencato in §6.

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

## 5. Metriche di Redis (`redis_exporter`)

Sidecar nel pod `redis-cart` ([deploy/base/kustomization.yaml](../deploy/base/kustomization.yaml)), quindi uguale in dev e prod. Il Service `redis-cart` espone anche la porta `metrics` (9121), che userà il ServiceMonitor della fase 7.

Scelte:

- **Sidecar e non deployment separato:** parla con Redis su `localhost:6379`, quindi non serve aprire la NetworkPolicy di Redis (che ammette solo cartservice); riusa il Secret `redis-cart-auth` e segue il ciclo di vita di Redis.
- **Password da variabile d'ambiente** (`REDIS_PASSWORD`, dal Secret): non compare tra gli argomenti del processo, a differenza di `--requirepass` di Redis (limite già dichiarato in `docs/security.md`).
- **Immagine** `oliver006/redis_exporter:v1.97.0` fissata con digest dell'indice multi-arch (amd64, arm64, armv7), utente 59000, `readOnlyRootFilesystem`, `drop ALL`, richieste 10m/16Mi e limiti 50m/64Mi.
- **Probe su `/health`:** verificato in locale che risponde 200 anche con password sbagliata, quindi l'exporter non viene riavviato quando Redis è giù: è proprio il caso in cui deve segnalarlo.
- **Segnale per l'alert (fase 7):** con password sbagliata (o Redis irraggiungibile) l'exporter risponde ma con `redis_up 0` e `redis_exporter_last_scrape_error{err="WRONGPASS ..."} 1`. Le metriche utili sono `redis_up`, `redis_connected_clients`, `redis_memory_used_bytes`, `redis_commands_processed_total`, `redis_db_keys`.
- **Limite:** Redis non ha `maxmemory` e il limite del container è 256Mi: con `noeviction` (rilevato dall'exporter) un riempimento si traduce in OOMKilled, non in errori di scrittura. Utile per lo scenario di failure della fase 8.

Provato in locale (container Docker con `redis:alpine --requirepass`): password giusta → `redis_up 1` e metriche; password sbagliata → `redis_up 0` con errore esplicito. Il `kustomize build` di dev e prod contiene sidecar e porta del Service, `kubeconform` valido, e il dry-run lato server in k3d accetta Deployment e Service (Pod Security `restricted` inclusa). 

Provato nel cluster dopo il push (commit `58d2d340`, Flux ha applicato dev): pod `redis-cart` `2/2 Running`, 0 riavvii; `/metrics` letto dalla porta `metrics` del Service (via `port-forward`) con `redis_up 1`, `redis_exporter_last_scrape_error 0`, 3 client connessi, 5 chiavi in `db0`, circa 1,7 MB di memoria; lo smoke test (carrello e checkout intero) passa con il Redis riavviato, quindi il sidecar non disturba cartservice. Il riavvio del pod ha azzerato i carrelli esistenti (`emptyDir`), come previsto. **Non provato:** il caso di guasto nel cluster (`redis_up 0` visto solo in locale); la raccolta da parte di Prometheus (fase 7, e la NetworkPolicy di Redis dovrà ammettere il namespace `monitoring` sulla 9121); prod, che riceverà il sidecar solo con la PR `main → prod`.

## 6. Log strutturati

Controllati a runtime in dev (ultime 200 righe di ogni servizio, circa 20 minuti di traffico del loadgenerator): per ogni riga ho verificato che sia un oggetto JSON valido. Il risultato conferma l'analisi dal codice di fase 1.

| Servizio | Formato | Campo tempo / livello |
|---|---|---|
| checkoutservice, productcatalogservice, shippingservice | JSON (logrus) | `timestamp`, `severity`, `message` |
| frontend | JSON (logrus), più campi `http.*` | `timestamp`, `severity`, `message` |
| emailservice, recommendationservice | JSON (python-json-logger) | `timestamp`, `severity`, `message`, `name` |
| currencyservice, paymentservice | JSON (pino) | `time`, `severity`, `message`, `name`, `pid`, `hostname` |
| adservice | JSON (log4j2 `JsonLayout`) | `instant`, **`level`** (non `severity`), `message`, `logging.googleapis.com/*` |
| **cartservice** | **testo** (`Console.WriteLine`) | nessuno |
| **loadgenerator** | **testo** (shell e Locust) | nessuno |
| redis-cart | testo (formato Redis); il sidecar usa logfmt | nessuno |

Cosa ne segue:

- **I nomi dei campi non sono uniformi**: il livello è `severity` in 9 servizi su 10 (adservice usa `level`) e il tempo è `timestamp`, `time` o `instant`. Una query unica sui log dovrebbe normalizzarli. Lo stack della fase 7 non include un aggregatore di log (solo Prometheus), quindi oggi non è un problema operativo: resta `kubectl logs`.
- **cartservice e loadgenerator non emettono JSON.** Non li ho modificati: fuori dal perimetro della fase 5 (il cartservice è codice .NET upstream).
- **Frontend: righe non JSON a ogni visita della home.** `handlers.go:96` chiama `fmt.Println("env platform is either empty or invalid")` se `ENV_PLATFORM` non è impostata (63 righe in circa 20 minuti). Soluzione di configurazione, senza toccare il codice: `ENV_PLATFORM=local` nel Deployment (patch in `deploy/base/kustomization.yaml`). È il valore che il codice userebbe comunque, quindi la pagina non cambia.
- **Limite della verifica:** ho guardato le righe recenti in condizioni normali. Non ho controllato i percorsi di errore (stack trace, panic) né il formato dei log di avvio.

## 7. Probe

Quelle in uso sono le probe upstream (gRPC per i servizi, `/_healthz` per il frontend, `tcpSocket` per Redis) più i ritocchi del component `arm64-workaround` (timeout 5 s e ritardi iniziali, solo per i servizi emulati).

Cosa controllano davvero, letto nel codice:

- Frontend: `/_healthz` risponde "ok" senza contattare i backend.
- checkoutservice, productcatalogservice, shippingservice, emailservice, recommendationservice, currencyservice, paymentservice, adservice: rispondono `SERVING` in modo incondizionato.
- **cartservice:** il gestore ha un metodo `Ping()` che sembra controllare Redis, ma in `RedisCartStore.cs` è `try { return true; }`: **non controlla nulla**. (Avevo dedotto il contrario dalla sola firma del costruttore, prima di leggere il metodo: errore mio.)
- redis-cart: `tcpSocket` sulla 6379, quindi non verifica nemmeno la password.

**Prova nel cluster: Redis spento in dev per circa 100 s** (`kubectl scale --replicas=0`, poi ripristinato a 1; smoke test superato dopo).

| Istante | Frontend | cartservice | Home dallo shop |
|---|---|---|---|
| 20 s | `1/1` | `1/1` | **500** |
| 45 s | `1/1` | `0/1`, 1 riavvio | 500 |
| 75-100 s | `1/1` | `1/1` (Redis ancora spento) | 500 |

- Il frontend è rimasto `Ready` per tutta la prova mentre la home dava 500: conferma che le sue probe non vedono i backend.
- Il cartservice non è uscito dal servizio perché `NotServing`: gli eventi mostrano `Readiness probe failed: ... health rpc did not complete within 5s`, cioè **timeout** della chiamata di health. Poiché la liveness usa la stessa chiamata, il pod è stato riavviato una volta. È tornato `Ready` a Redis ancora spento, quindi **`Ready` non significa "funziona"**.
- **Causa dei timeout: non indagata.** L'ipotesi è che richieste bloccate su Redis saturino il servizio (che gira emulato), ma non l'ho dimostrato.

**Decisione: nessuna probe modificata.** Una readiness che dipende da un backend condiviso toglie tutte le repliche dal servizio insieme, quando Redis cade, e il frontend risponderebbe 503 al posto di 500 senza che nulla migliori. Il rilevamento dei guasti sta nelle metriche, non nelle probe: tasso di 5xx del frontend (§1) e `redis_up` (§5), da trasformare in alert in fase 7.

Altre osservazioni, non corrette:

- Il riavvio del cartservice quando Redis cade non cura nulla (il problema è Redis); è un buon scenario per la fase 8.
- Nessuna `startupProbe`: i servizi lenti all'avvio (JVM, .NET emulati) si affidano a `initialDelaySeconds: 60` della liveness, aggiunto dal workaround. Quando la fase 6 toglie l'emulazione e il workaround, **le probe vanno riverificate sulle immagini native**.
- Il loadgenerator non ha probe (non espone porte).
- Il frontend ha `timeoutSeconds: 1`: non ha dato problemi in circa 19 ore (0 riavvii), ma non l'ho messo sotto carico.

## 8. Ancora da fare in fase 5

Blackbox exporter per il frontend (opzionale, non fatto). La build multi-arch degli altri servizi e la riverifica delle probe sono in fase 6.
