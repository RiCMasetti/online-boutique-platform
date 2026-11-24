# Online Boutique su Kubernetes: piattaforma GitOps locale (Challenge L2)

Questo repository è un fork di [Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo) di Google. Il codice dell'applicazione è quasi tutto invariato. Il lavoro è intorno: come si installa, si promuove, si osserva, si rompe e si ripara.

Il README descrive **cosa c'è, come si usa e che cosa è stato provato**. Il resto sta nei documenti collegati nella [mappa dei documenti](#mappa-dei-documenti). Per la regola «nessun comando non eseguito», ogni comando riporta che cosa lo ha verificato: vedi [Stato della verifica](#stato-della-verifica).

> **Comandi dalla radice del repository.** Gli script e i percorsi (`scripts/…`, `deploy/…`) sono relativi alla radice, non a questa cartella.

## Indice

1. [Perché Online Boutique](#perché-online-boutique)
2. [Cosa c'è nel cluster](#cosa-cè-nel-cluster)
3. [Prerequisiti](#prerequisiti)
4. [Installazione](#installazione)
5. [Segreti](#segreti)
6. [Build e test](#build-e-test)
7. [Verifica e demo](#verifica-e-demo)
8. [Aggiornamento, promozione e rollback](#aggiornamento-promozione-e-rollback)
9. [Osservabilità](#osservabilità)
10. [Guasti riproducibili](#guasti-riproducibili)
11. [Mappa dei documenti](#mappa-dei-documenti)
12. [Stato della verifica](#stato-della-verifica)
13. [Limiti e scelte non fatte](#limiti-e-scelte-non-fatte)

## Perché Online Boutique

[Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo) è un negozio online di esempio: si sfoglia il catalogo, si riempie il carrello, si paga (con carta e spedizione finte). **Dominio: e-commerce.** È composto da 11 microservizi in cinque linguaggi (Go, C#, Node.js, Python, Java) che parlano tra loro in gRPC, più un Redis per il carrello. Upstream: [GoogleCloudPlatform/microservices-demo](https://github.com/GoogleCloudPlatform/microservices-demo), licenza Apache 2.0.

Perché è adatta a questo lavoro:

- **È un sistema distribuito vero, ma piccolo.** Ha dipendenze tra servizi, un punto di stato (Redis), un ordine di avvio e guasti che si propagano in modo diverso (un backend sbagliato dà errori 500 con pod `Ready`; una variabile mancante dà `CrashLoopBackOff`). Serve per esercitare diagnosi e rollback ([runbook](../docs/runbook.md)).
- **Funziona su qualunque Kubernetes** e ha già una base Kustomize e un component di NetworkPolicy, che gli overlay riusano senza copiarli.
- **Non ha metriche, dashboard né pipeline sue** (quelle upstream sono legate a un progetto Google Cloud e su un fork non funzionano): sono lavoro nostro, non qualcosa che c'era già.

Come sono mappati i componenti generici della traccia sull'app reale:

| Componente della traccia | Nell'app | Nota |
|---|---|---|
| API service | `frontend` (Go, HTTP) | punto d'ingresso, unico esposto dall'Ingress |
| Database / cache | `redis-cart` | unico stato; senza persistenza (`emptyDir`) |
| Worker | **non presente** | il `loadgenerator` genera traffico, non elabora code |

**Parti usate:** `src/` (11 servizi) e `kustomize/base`, riusata come base degli overlay. **Parti nostre:** `deploy/`, `clusters/`, `infrastructure/`, `observability/`, `scripts/`, `krateo/`, `.github/workflows/` e il frontend modificato (`/metrics`, [dettagli](../docs/observability.md)). **Parti upstream non usate** da questa piattaforma e rimaste per non toccare la cronologia: `terraform/`, `helm-chart/`, `istio-manifests/`, `kubernetes-manifests/`, `release/`, `skaffold.yaml`, `cloudbuild.yaml`, `.deploystack/` e `kustomize/components/*` tranne `network-policies`. Il `shoppingassistantservice` non è nella base e non è distribuito.

Analisi completa, diagramma e tabella servizio/protocollo/dipendenze: [docs/architecture.md](../docs/architecture.md).

## Cosa c'è nel cluster

Un cluster **k3d** con un nodo, nel quale **Flux** riconcilia il repository ogni minuto:

| Elemento | Segue | Dove |
|---|---|---|
| `boutique-dev` (namespace `boutique-dev`) | branch `main` | `deploy/overlays/dev`, loadgenerator attivo |
| `boutique-prod` (namespace `boutique-prod`) | branch `prod` | `deploy/overlays/prod`, 2 repliche di frontend e catalogo |
| `infrastructure`, `observability-stack`, `observability-config` | `main` | `infrastructure/`, `observability/`: kube-prometheus-stack, ServiceMonitor, alert, dashboard |

| Servizio | URL locale |
|---|---|
| Shop dev | http://boutique-dev.localtest.me:8080 |
| Shop prod | http://boutique-prod.localtest.me:8080 |
| Grafana | http://grafana.localtest.me:8080 (utente `admin`, password in [`docs/observability.md`](../docs/observability.md) §8) |

`*.localtest.me` risolve a 127.0.0.1: nessuna modifica a `/etc/hosts`. Il resto (immagini in GHCR per `amd64` e `arm64`, tag = SHA del commit, CI) è in [docs/ci.md](../docs/ci.md); le scelte e le alternative scartate sono negli [ADR](../docs/adr/).

## Prerequisiti

Versioni **con cui è stato provato** (macOS, Docker in una VM Linux `aarch64` con 6 CPU e circa 9,7 GiB di RAM). Versioni diverse non sono state provate.

| Strumento | Versione provata | Serve per |
|---|---|---|
| Docker | 29.9.3 | cluster k3d, build |
| k3d | 5.9.0 (k3s v1.36.4) | cluster locale |
| kubectl | 1.36.1 | tutto |
| Flux CLI | 2.8.6 | bootstrap, `flux get` |
| kustomize | 5.8.3 | `scripts/apply-local.sh`, controlli |
| sops / age | 3.13.3 / 1.3.2 | segreti |
| gh | 2.104.0 | token per il bootstrap, PR |
| kubeconform / hadolint | 0.8.0 / 2.15.1 | controlli statici (opzionali) |

**Risorse:** la stima del piano era di 6-8 GB di RAM per Docker per app e stack Prometheus. Misurato il 2026-11-23 con dev, prod, Flux e lo stack acceso: *requests* al 66% della CPU e al 40% della memoria del nodo (6 CPU, circa 9,7 GiB), uso reale 754 mCPU e 5,4 GiB (54%). Grafana può saturare la CPU se si aprono pagine che lanciano molte query ([caso AI-17](../AI-LOG.md)): chiudile quando non servono.

## Installazione

Sono provati due percorsi. **Prima di usarli su un repository che non è questo fork, leggi [Segreti](#segreti) e [Cosa va cambiato su un altro fork](#cosa-va-cambiato-su-un-altro-fork).**

### A. Con Flux (percorso normale)

```bash
scripts/cluster-up.sh                                        # cluster k3d "boutique", 8080 -> Traefik
GITHUB_TOKEN="$(gh auth token)" scripts/flux-bootstrap.sh    # Secret sops-age, flux bootstrap, Kustomization
git pull                                                     # il bootstrap committa clusters/local/flux-system/
flux --context k3d-boutique get kustomizations               # tutte READY True
```

Su un cluster nuovo Flux applica da solo infrastruttura, dev, prod e stack di osservabilità: non serve `apply-local.sh`. Dettagli e perché: [docs/gitops.md](../docs/gitops.md).

Il token serve solo per chiamare l'API di GitHub durante il bootstrap: non viene salvato né nel cluster né nel repository. Il token di `gh` è più ampio di un PAT dedicato.

### B. Senza Flux (solo app, un ambiente alla volta)

```bash
scripts/cluster-up.sh
scripts/apply-local.sh dev      # decifra i Secret con la chiave age locale e applica l'overlay
scripts/smoke-test.sh
```

Non usarlo su un cluster già gestito da Flux: i due si contenderebbero gli oggetti.

### Distruggere e ricreare

```bash
k3d cluster delete boutique
```

## Segreti

L'app non ha segreti reali. È stato **costruito** un caso per mostrare il flusso: la password di Redis (dev e prod) e la password di Grafana, cifrate con **SOPS + age** nei file:

- `deploy/overlays/dev/redis-auth.enc.yaml`
- `deploy/overlays/prod/redis-auth.enc.yaml`
- `observability/stack/grafana-admin.enc.yaml`

`.sops.yaml` contiene solo la chiave **pubblica** age. La chiave **privata** sta in `~/.config/sops/age/keys.txt`, fuori dal repository, e non va mai committata né incollata altrove. In Flux la usa il Secret `sops-age` nel namespace `flux-system`, creato da `scripts/flux-bootstrap.sh` e non presente in Git.

**Chi clona questo repository non ha quella chiave** e quindi non può decifrare questi tre file: né Flux né `apply-local.sh` funzioneranno finché non si sostituiscono (sotto). Flusso, chi fa cosa e limiti: [docs/security.md](../docs/security.md) §2.

### Cosa va cambiato su un altro fork

| Cosa | Dove | Perché |
|---|---|---|
| Chiave age e i tre `*.enc.yaml` | `.sops.yaml`, file sopra | si cifrano con la propria chiave pubblica; valori nuovi, quelli vecchi non sono recuperabili |
| Proprietario e nome del repository | `GITHUB_OWNER` e `GITHUB_REPO` per `scripts/flux-bootstrap.sh`; URL in `clusters/local/boutique-prod-source.yaml` | il bootstrap scrive sul repository e registra una deploy key |
| Registro delle immagini | `ghcr.io/ricmasetti/online-boutique-platform/…` in `deploy/components/dev-images/` e `deploy/overlays/prod/` | senza la propria CI il tag indicato non esiste nel proprio registro; i pacchetti GHCR vanno resi pubblici a mano ([docs/ci.md](../docs/ci.md) §3) |
| Branch `prod` | repository | non c'è finché non viene creato |

**Questo percorso non è stato provato da qualcuno diverso dall'autore**: la chiave age è la mia, il repository è il mio. Vedi [Stato della verifica](#stato-della-verifica).

## Build e test

**Controlli statici** (gli stessi della CI, [`.github/workflows/checks.yaml`](../.github/workflows/checks.yaml)):

```bash
kustomize build deploy/overlays/dev  > /tmp/dev.yaml
kustomize build deploy/overlays/prod > /tmp/prod.yaml
kubeconform -strict -skip Secret -summary -kubernetes-version 1.33.0 /tmp/dev.yaml
kubeconform -strict -skip Secret -summary -kubernetes-version 1.33.0 /tmp/prod.yaml
```

`-skip Secret` serve perché il Secret cifrato con SOPS ha una chiave `sops:` non ammessa dallo schema Kubernetes.

**Immagine del frontend** (modificata per le metriche; richiede BuildKit):

```bash
cd src/frontend
docker buildx build --platform linux/arm64 -t boutique/frontend:phase5 --load .
```

**Test:** `go test ./...` in `src/frontend`, `src/productcatalogservice`, `src/shippingservice` e `src/checkoutservice`; `dotnet test src/cartservice/` gira in CI. **Build e push di tutti gli 11 servizi** (`amd64` + `arm64`, runner nativi, tag = primi 12 caratteri dello SHA) avvengono in CI al push su `main`, non a mano: [docs/ci.md](../docs/ci.md).

## Verifica e demo

I passi seguono l'ordine della demo. Controlli rapidi:

```bash
scripts/smoke-test.sh                                          # dev: 7 controlli, checkout incluso
scripts/smoke-test.sh http://boutique-prod.localtest.me:8080   # prod
kubectl --context k3d-boutique -n boutique-dev get pods
flux --context k3d-boutique get kustomizations
scripts/netpol-test.sh                                         # le NetworkPolicy bloccano davvero (dev; accetta un namespace)
```

**Attenzione: `Ready` non basta.** Le probe non guardano le dipendenze: un frontend con un backend sbagliato è `Ready` e risponde 500. Per questo lo smoke test usa il checkout intero e gli alert si basano sulle richieste. Albero di diagnosi: [docs/runbook.md](../docs/runbook.md) §2.

| # | Passo della demo | Dove |
|---|---|---|
| 1 | Struttura del repository | [Mappa dei documenti](#mappa-dei-documenti) |
| 2 | Build dell'immagine | [Build e test](#build-e-test), [docs/ci.md](../docs/ci.md) |
| 3 | Installazione | [Installazione](#installazione) |
| 4 | Pod, service, ingress, configurazione | comandi sopra, [docs/runbook.md](../docs/runbook.md) §1 |
| 5 | Endpoint principali | `scripts/smoke-test.sh` |
| 6 | Health, readiness, log, metriche | [Osservabilità](#osservabilità) |
| 7 | Aggiornamento e rollout | [sotto](#aggiornamento-promozione-e-rollback) |
| 8 | Guasto | [Guasti riproducibili](#guasti-riproducibili) |
| 9 | Rollback | [docs/runbook.md](../docs/runbook.md) §4, **non provato** |
| 10 | Valutazione Krateo | [docs/krateo-evaluation.md](../docs/krateo-evaluation.md), [ADR 0005](../docs/adr/0005-krateo-non-adottare-ora.md) |
| 11 | Uso dell'AI | [ai-usage.md](ai-usage.md), [AI-LOG.md](../AI-LOG.md) |

La checklist con i tempi misurati nelle due prove generali da cluster distrutto è in [docs/demo-checklist.md](../docs/demo-checklist.md).

## Aggiornamento, promozione e rollback

```
PR verso main ──► checks (hadolint, kustomize+kubeconform, test)
push su main  ──► build 11 servizi × 2 architetture ──► GHCR ──► commit del tag ──► Flux ──► dev
PR main → prod ──► merge ──► Flux ──► prod
```

- **dev** segue `main`; **prod** segue il branch `prod`, che avanza solo con una PR `main → prod`: il merge è l'atto di promozione ([ADR 0003](../docs/adr/0003-promozione-prod-via-branch.md)). Oggi «solo con PR» è una convenzione: senza branch protection un push diretto è possibile.
- La CI non tocca prod. Dopo ogni release serve `git pull`, perché la CI committa il tag su `main`.
- **Stato di prod:** può essere indietro rispetto a `main` finché non si apre la PR di promozione. Nel cluster al momento della stesura prod è a `prod@7a723188`, indietro rispetto a `main`; i target Prometheus di prod risultano `down` finché le NetworkPolicy aggiornate non vengono promosse ([docs/observability.md](../docs/observability.md) §8).
- **Rollback corretto:** `git revert` e push (dev) o PR (prod). `kubectl rollout undo` non dura: Flux riporta lo stato di Git. Per un intervento manuale temporaneo serve prima `flux suspend`. **Provato**: il revert di un cambio di repliche in dev (circa 55 s). **Non provato**: il revert di un commit sbagliato su prod e `rollout undo` contro Flux ([docs/runbook.md](../docs/runbook.md) §4).

## Osservabilità

- **Metriche del frontend:** `/metrics` con `frontend_http_requests_total` e `frontend_http_request_duration_seconds` (etichette `method`, `route`, `code`). `redis_exporter` come sidecar di `redis-cart`.
- **kube-prometheus-stack** (Helm, via Flux): ServiceMonitor, dashboard `Online Boutique: panoramica`, quattro alert (`FrontendUnavailable`, `PodCrashLooping`, `RedisDown`, `FrontendHigh5xxRate`).
- **Log:** JSON in 9 dei 11 servizi applicativi, verificato riga per riga a runtime; `cartservice` e `loadgenerator` emettono testo ([docs/observability.md](../docs/observability.md) §6). I nomi dei campi non sono uniformi (`severity` o `level`; `timestamp`, `time` o `instant`), e non c'è un aggregatore di log: si usa `kubectl logs`.
- Prometheus: `kubectl --context k3d-boutique -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090`.

Provato nel cluster: target `up` in dev, `RedisDown` e `FrontendHigh5xxRate` scattati con Redis spento; `FrontendUnavailable` e `PodCrashLooping` con `break-it.sh`. Problema aperto: **Grafana** satura la CPU se si aprono pagine che lanciano molte query. Causa probabile, non provata ([docs/observability.md](../docs/observability.md) §8).

## Guasti riproducibili

```bash
scripts/break-it.sh <scenario>      # image-tag | bad-addr | missing-addr | low-memory | frontend-down
scripts/break-it.sh status
scripts/break-it.sh restore
```

Lavora solo su `k3d-boutique` e sul namespace `boutique-dev`. Sospende la Kustomization Flux di dev (altrimenti Flux annulla il guasto), modifica il cluster con `kubectl` e non tocca Git; `restore` riprende Flux e **fallisce** se un Deployment non è pronto. Per ogni scenario: sintomo, diagnosi, causa, fix e tempi misurati in [docs/runbook.md](../docs/runbook.md) §3. Ripristino misurato: 6-21 s. **I guasti li ho scelti io e sapevo la risposta**: i tempi misurano il ripristino, non la qualità della diagnosi.

## Mappa dei documenti

| Documento | Contenuto |
|---|---|
| [architecture.md](../docs/architecture.md) | servizi, protocolli, dipendenze, avvio e guasti, punti critici |
| [gitops.md](../docs/gitops.md) | Flux, promozione, rollback, comandi |
| [security.md](../docs/security.md) | hardening, NetworkPolicy, SOPS, limiti residui |
| [ci.md](../docs/ci.md) | workflow, immagini multi-arch, Trivy, esiti |
| [observability.md](../docs/observability.md) | metriche, log, probe, stack, Grafana |
| [runbook.md](../docs/runbook.md) | controllo rapido, diagnosi, scenari, rollback |
| [krateo-evaluation.md](../docs/krateo-evaluation.md) | valutazione, golden path, blueprint in [`krateo/`](../krateo/) |
| [adr/](../docs/adr/) | cinque decisioni con alternative scartate |
| [ai-usage.md](ai-usage.md) | uso dell'AI nelle cinque aree, con limiti |
| [consistency-check.md](consistency-check.md) | controllo di coerenza dei documenti |
| [AI-LOG.md](../AI-LOG.md) | diario di lavoro: prompt, decisioni, errori |
| [PIANO_DI_LAVORO.md](../PIANO_DI_LAVORO.md) | piano per fasi, con stato |

## Stato della verifica

| Cosa | Stato |
|---|---|
| Installazione con `apply-local.sh` da cluster cancellato (fase 3) | provata, 2026-11-19 |
| **Installazione con Flux da cluster cancellato** | **provata, 2026-11-23**: `k3d cluster delete`, `scripts/cluster-up.sh`, `scripts/flux-bootstrap.sh`. 6 Kustomization `Ready` circa 3 minuti dopo il bootstrap, nessun commit creato dal bootstrap, nessun intervento manuale |
| Smoke test dev e prod | rieseguito il 2026-11-23: 7/7 in entrambi |
| `kustomize build` + `kubeconform` dev e prod | rieseguito il 2026-11-23: 0 invalidi (50 e 47 risorse valide, il Secret cifrato escluso) |
| Cluster in esecuzione | 6 Kustomization Flux `Ready`, dev 12/12 pod `Running` il 2026-11-23 |
| Percorso di un **altro** utente (chiave age, fork, GHCR) | **non provato** |
| README provato da zero su cluster pulito | **fatto per il percorso A** (2026-11-23, riga sopra); smoke test 7/7 in dev e in prod, Grafana `/api/health` 200, 0 riavvii in `boutique-dev`, `boutique-prod` e `monitoring`. Il percorso B (`apply-local.sh`) non è stato rieseguito oggi (ultima prova 2026-11-19). **Fatto dallo stesso autore, sulla stessa macchina, con la chiave age già presente**: non è la prova di un altro utente |
| Rollback GitOps di un commit sbagliato | **non provato** |

Un quadro più dettagliato, comando per comando, è in [consistency-check.md](consistency-check.md).

## Limiti e scelte non fatte

- Un solo cluster e un solo nodo: dev e prod condividono nodo e control plane, senza isolamento di risorse.
- Redis senza persistenza, TLS né rotazione dei segreti; traffico gRPC in chiaro; uscita di rete non limitata (la NetworkPolicy upstream restringe solo l'ingresso). Elenco: [docs/security.md](../docs/security.md) §3.
- Trivy trova vulnerabilità HIGH/CRITICAL nelle immagini upstream: riportate in [docs/ci.md](../docs/ci.md) §4, **non analizzate né corrette**.
- Krateo: **non adottato ora** (ADR 0005); esiste un blueprint con controlli statici, **nessun PoC**.

---

Online Boutique è © Google, licenza Apache 2.0 ([LICENSE](../LICENSE)). Questo fork aggiunge la piattaforma descritta sopra; le modifiche al codice dell'applicazione sono il frontend (`/metrics`), i Dockerfile (default di architettura rimossi) e una correzione in `checkoutservice`.
