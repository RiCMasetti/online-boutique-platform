# Piano di lavoro — Challenge L2 (Online Boutique)

## 1. Decisioni di progetto (ADR sintetici)

| Tema | Scelta | Motivazione | Alternativa scartata |
|---|---|---|---|
| Workload | Google Online Boutique | 11 microservizi gRPC, Redis, loadgenerator, già pensato per K8s, ha base Kustomize upstream | — |
| Cluster | k3d | Leggero, rapido da ricreare, ingress Traefik incluso, port-mapping semplice | kind, minikube |
| Packaging app | **Kustomize** (base upstream + overlay `dev`/`prod`) | Riuso upstream, patch leggibili, integrazione nativa Flux | Helm (chart separato da mantenere) |
| GitOps | Flux | Kustomization nativa, `HelmRelease` per lo stack di piattaforma | Argo CD |
| Metriche | Prometheus (kube-prometheus-stack) | Standard de facto, ServiceMonitor, Grafana inclusa | OTel-only |
| Secret | SOPS + age con Flux | Secret cifrati nel repo, nessun valore in chiaro | Sealed Secrets |
| Registry / CI | GitHub Actions + GHCR | Gratuito, integrato col fork | GitLab CI |
| Ambienti | Namespace `boutique-dev` e `boutique-prod` nello stesso cluster | Sufficiente per i requisiti | Due cluster |

Ogni decisione va riportata in `docs/adr/` con data, contesto e trade-off.

## 2. Struttura del repository (target)

```
.
├── README.md                    # prerequisiti, build, deploy, test, demo, motivazione scelta app
├── docs/
│   ├── architecture.md          # componenti, flussi gRPC/HTTP, diagramma
│   ├── runbook.md               # verifica, troubleshooting, rollback
│   ├── krateo-evaluation.md     # valutazione + disegno di integrazione
│   ├── ai-usage.md              # uso AI (vedi AI-LOG.md)
│   ├── demo-checklist.md
│   └── adr/
├── AI-LOG.md                    # diario vivo di prompt/output/verifiche (da giorno 1)
├── src/                         # fork upstream (frontend modificato per metriche)
├── deploy/
│   ├── base/                    # base upstream + patch comuni
│   ├── components/              # network-policies, service-accounts, ecc.
│   └── overlays/{dev,prod}/
├── clusters/local/              # config Flux (sources, kustomizations)
│   ├── flux-system/
│   ├── infrastructure/          # kube-prometheus-stack, ingress, SOPS
│   └── apps/
├── observability/               # ServiceMonitor, dashboard Grafana, PrometheusRule
├── krateo/                      # blueprint / YAML concettuale (o PoC)
├── scripts/                     # cluster-up.sh, smoke-test.sh, break-it.sh, fix-it.sh
└── .github/workflows/
```

## 3. Fasi

L'ordine è pensato per avere presto una **fetta verticale funzionante** (app in cluster) e iterare. Le stime sono in effort relativo (S/M/L) perché non conosco la tua scadenza.

### Fase 0 — Setup e governance (S)
- [ ] Fork di `GoogleCloudPlatform/microservices-demo` su GitHub (**pubblico fin dal giorno 1**: un fork di un repo pubblico non può essere reso privato) e clone.
- [ ] Igiene del repo prima del primo commit: `.gitignore` (chiavi age, `.env`, kubeconfig), pre-commit con `gitleaks`, disattiva o rimuovi i workflow upstream che non servono.
- [ ] Verifica tool: Docker, k3d, kubectl, kustomize, flux CLI, sops, age, kubeconform, hadolint.
- [ ] Verifica risorse Docker: servono circa 6-8 GB di RAM per app + stack Prometheus.
- [ ] Crea `AI-LOG.md` con il template (strumento, obiettivo, prompt, output, accettato/modificato/scartato, verifica).
- [ ] Prima ADR: scelte della tabella sopra.

**Done quando:** repo pronto e AI-LOG con la prima voce.

### Fase 1 — Analisi dell'applicazione (M) — peso 18%
- [ ] Esplora la struttura: servizi, linguaggi, porte, variabili d'ambiente `*_SERVICE_ADDR`, dipendenze.
- [ ] Usa l'AI per la mappa iniziale e **valida a mano** leggendo manifest e `.proto`; annota cosa hai confermato e cosa hai corretto.
- [ ] Disegna il diagramma: browser → frontend (HTTP) → servizi (gRPC) → Redis (cart).
- [ ] Mappa i componenti richiesti dalla traccia sull'app reale: *API Service* = frontend, *DB/cache* = Redis, *worker* = non presente (loadgenerator come generatore di traffico). Dichiaralo apertamente.
- [ ] Elenca i punti critici di deploy: ordine di avvio, dipendenze, risorse, Redis non persistente.

**Done quando:** `docs/architecture.md` con diagramma e tabella servizio/protocollo/dipendenze.

### Fase 2 — Cluster e deploy base (M)
- [ ] `scripts/cluster-up.sh`: `k3d cluster create` con port-mapping `8080:80@loadbalancer`.
- [ ] Deploy della base upstream con `kubectl apply -k` come primo test (poi passerà a Flux).
- [ ] Ingress Traefik con host tipo `boutique-dev.localtest.me` (risolve a 127.0.0.1, nessuna modifica a `/etc/hosts`).
- [ ] Verifica pod, service, endpoint e navigazione dello shop.

**Done quando:** lo shop risponde su `http://boutique-dev.localtest.me:8080`.

### Fase 3 — Overlay, hardening e configurazione (M-L) — Sicurezza 7%
- [ ] Overlay `dev` e `prod`: namespace, repliche, resources requests/limits, host ingress, tag immagini. Loadgenerator attivo solo in `dev`.
- [ ] Service account: la base upstream ne definisce già uno per servizio (11, nessuno per `redis-cart`; non esiste un component dedicato). Imposta `automountServiceAccountToken: false` con una patch, e valuta un SA anche per Redis.
- [ ] NetworkPolicy (component upstream) con default-deny. Verifica che il controller di k3s le applichi davvero.
- [ ] `securityContext` (non-root, readOnlyRootFilesystem, drop capabilities) dove l'app lo consente; documenta le eccezioni.
- [ ] Secret: l'app non ha secret reali, quindi crea un caso onesto (es. password Redis o credenziale di test) gestito con SOPS+age. Dichiara che è un caso costruito per la challenge.
- [ ] Documenta i limiti residui (Redis senza persistenza, cluster unico, nessuna rotazione secret, ecc.).

**Done quando:** `kustomize build` produce dev e prod diversi e validi, con policy attive.

### Fase 4 — Flux GitOps (M) — Automazione 10%
- [ ] `flux bootstrap github` sul fork (token solo da variabile d'ambiente, mai nel repo né nei prompt).
- [ ] `Kustomization` Flux per infrastruttura, `dev` e `prod`, con `dependsOn` corretto e decryption SOPS.
- [ ] Promozione: `dev` segue `main`; `prod` si aggiorna solo con PR/tag esplicito.
- [ ] Da qui in poi **ogni cambio passa da Git**.

**Done quando:** un commit su `main` aggiorna `dev` senza `kubectl apply` manuale.

### Fase 5 — Immagine custom, Dockerfile e metriche (M-L) — Implementazione 15%, Osservabilità 8%
Upstream non espone metriche Prometheus, quindi serve una modifica mirata (consentita dalla traccia).
- [ ] **Metrica applicativa:** nel `frontend` (Go) aggiungi `promhttp` con `/metrics` e un contatore/istogramma delle richieste HTTP. Modifica minima e documentata nel diff.
- [ ] Dockerfile (multi-stage) e build riproducibile; variabili d'ambiente documentate; esecuzione locale con `docker run`.
- [ ] Build **multi-arch** (`linux/amd64` + `linux/arm64`, `docker buildx`) del frontend, da estendere a tutti gli 11 servizi in fase 6. Le immagini upstream sono solo amd64 (ADR 0002).
- [ ] **Metriche di supporto:** `redis_exporter` come sidecar o deployment separato; probe del frontend con blackbox exporter (opzionale).
- [ ] Log strutturati: verifica che i servizi emettano JSON (upstream usa logrus/JSON in molti servizi) e documenta quali.
- [ ] Probe liveness/readiness: verifica quelle upstream (`/_healthz` per il frontend, probe gRPC per gli altri) e correggi se necessario.

**Piano B se il tempo stringe:** solo `redis_exporter` + kube-state-metrics + cAdvisor, spiegando perché non hai toccato il frontend.

**Done quando:** Prometheus mostra la metrica del frontend con traffico del loadgenerator.

### Fase 6 — CI GitHub Actions (M) — Automazione 10%
- [ ] Lint: `hadolint` sui Dockerfile modificati, `kubeconform` e `kustomize build` su dev e prod.
- [ ] Test: `go test` del frontend (e dei servizi toccati).
- [ ] Build e push su GHCR con tag = SHA, **per tutti gli 11 servizi** (matrice) e per `amd64` e `arm64` (ADR 0002). Verifica: runner arm64 disponibili per il fork pubblico? Pacchetti impostati come pubblici?
- [ ] Passare gli overlay alle immagini GHCR e **rimuovere i workaround** di `deploy/overlays/dev` (probe rilassate, limiti di memoria).
- [ ] Aggiornamento del tag nell'overlay `dev` (commit automatico o PR) in modo che Flux faccia il rollout.
- [ ] Scansione immagine (Trivy) come plus, non bloccante.

**Done quando:** una PR fa girare i controlli; il merge produce un'immagine e un rollout in `dev`.

### Fase 7 — Stack di osservabilità (M) — Osservabilità 8%
- [ ] `HelmRelease` di kube-prometheus-stack gestito da Flux.
- [ ] `ServiceMonitor` per frontend e Redis exporter.
- [ ] Dashboard Grafana: richieste/s, latenza, errori 5xx, restart pod, stato Redis.
- [ ] 2-3 `PrometheusRule` utili agli scenari di failure (pod in crash loop, 5xx alti, frontend non disponibile).

**Done quando:** dashboard leggibile e almeno un alert che scatta nello scenario di failure.

### Fase 8 — Failure scenario, runbook, rollback (L) — Troubleshooting 20%
Fase più pesante: dedicale tempo vero.
- [ ] `scripts/break-it.sh` con almeno 3 guasti riproducibili:
  1. Tag immagine inesistente → `ImagePullBackOff`.
  2. Variabile `*_SERVICE_ADDR`: **sbagliata** (valore non vuoto) → pod sani ma errori gRPC/500 a ogni richiesta; **rimossa o vuota** → `CrashLoopBackOff` (es. checkout o frontend). Dal codice i client gRPC sono lazy (`grpc.NewClient`), quindi il crash loop non si ottiene con un valore sbagliato. Vedi `docs/architecture.md` §4; da confermare a runtime.
  3. Limite memoria troppo basso → `OOMKilled`.
  - (opzionale) NetworkPolicy troppo restrittiva → timeout tra servizi.
- [ ] Per ciascuno: sintomo, ipotesi, comandi di diagnosi (`get`, `describe`, `logs --previous`, eventi, metriche), causa, fix, verifica.
- [ ] **Caso AI di troubleshooting** (obbligatorio): incolla (senza secret) eventi e log, registra prompt, ipotesi dell'AI, cosa hai verificato, cosa era sbagliato o incompleto.
- [ ] Rollback GitOps: `git revert` e riconciliazione Flux. Documenta la differenza con `kubectl rollout undo` e perché Flux lo annullerebbe (serve `flux suspend` prima).
- [ ] `docs/runbook.md`: checklist di verifica, albero di diagnosi, rollback, criteri di escalation.

**Done quando:** puoi rompere e riparare ogni scenario in meno di 5 minuti, spiegando la diagnosi.

### Fase 9 — Valutazione Krateo (M) — Krateo 5%
- [ ] Studia la documentazione corrente di Krateo (non fidarti della memoria o dell'AI: verifica).
- [ ] Individua il golden path: "nuovo ambiente Boutique" come template.
- [ ] Parametri da esporre: nome servizio, namespace, ambiente, risorse, ingress host, repository, owner, tier.
- [ ] Chiarisci cosa Krateo orchestra (risorse K8s, pipeline, DB) e cosa resta a Flux.
- [ ] Benefici, prerequisiti, limiti, rischi; distingui **PoC / blueprint / adozione reale**.
- [ ] Artefatto: diagramma di integrazione + YAML concettuale (chart wrapper per la composition). PoC solo se avanza tempo.
- [ ] Il chart wrapper deve avere un `values.schema.json` nella root: la doc di Krateo lo indica come prerequisito di una `CompositionDefinition` (fonte in AI-LOG, AI-01). Lo schema coincide con i parametri esposti nel golden path. Rileggi la pagina direttamente, il controllo fatto finora è solo un riassunto.
- [ ] Raccomandazione argomentata: se, quando e come adottarlo.

### Fase 10 — Documentazione finale e sezione AI (M)
- [ ] README completo (prerequisiti, build, deploy, test, demo) **provato da zero su un cluster pulito**.
- [ ] Sezione "Perché Online Boutique" con link, dominio e parti usate.
- [ ] `docs/ai-usage.md`: cinque aree richieste dalla traccia (analisi, implementazione, operations, documentazione/demo, governance), con limiti e valore.
- [ ] Controllo di coerenza: nessun comando nei doc che non hai eseguito.

### Fase 11 — Prova generale della demo (S-M)
- [ ] `docs/demo-checklist.md` con i comandi in ordine e i tempi.
- [ ] Prova completa da cluster distrutto (`k3d cluster delete`) a demo finita, almeno due volte.
- [ ] Piano B per rete assente: immagini pre-scaricate, registro locale o `k3d image import`.

## 3bis. Calendario (10 giorni)

| Giorno | Fasi | Obiettivo di fine giornata |
|---|---|---|
| 1 | 0, 1 (inizio) | Fork pubblico, tool verificati, `AI-LOG.md` avviato, mappa dei servizi |
| 2 | 1 (fine), 2 | `architecture.md` con diagramma; shop raggiungibile su k3d |
| 3 | 3 | Overlay dev/prod, SA, NetworkPolicy, SOPS |
| 4 | 4 | Flux attivo: un commit su `main` aggiorna `dev` |
| 5 | 5 | Frontend con `/metrics`, Dockerfile, immagine eseguibile |
| 6 | 6, 7 (inizio) | CI verde, rollout automatico in `dev`, stack Prometheus installato |
| 7 | 7 (fine), 8 (inizio) | Dashboard e alert; primi due failure scenario |
| 8 | 8 | Terzo scenario, rollback GitOps, `runbook.md`, caso AI di troubleshooting |
| 9 | 9, 10 | Valutazione Krateo, README e `ai-usage.md` completi; **feature freeze a fine giornata** |
| 10 | 11 | Prova generale da cluster distrutto (2 volte), correzioni, buffer |

Regole: non iniziare una fase nuova se la precedente non ha il suo "done". Se a fine giorno 5 sei indietro, passa al piano B delle metriche. Dedica circa 30 minuti al giorno alla lettura della documentazione Krateo, così la fase 9 non parte da zero.

## 4. Mappa demo → artefatti

| # | Passo demo | Fase | Artefatto |
|---|---|---|---|
| 1 | Clone e struttura | 0, 1 | README, struttura repo |
| 2 | Build immagine | 5 | Dockerfile, CI |
| 3 | Installazione | 2, 4 | `cluster-up.sh`, Flux |
| 4 | Verifica pod/service/ingress/config | 2, 3 | runbook |
| 5 | Endpoint principali | 2 | `smoke-test.sh` |
| 6 | Health, readiness, log, metriche | 5, 7 | Grafana, probe |
| 7 | Aggiornamento e rollout | 4, 6 | PR → CI → Flux |
| 8 | Failure scenario | 8 | `break-it.sh`, alert |
| 9 | Rollback | 8 | `git revert`, runbook |
| 10 | Valutazione Krateo | 9 | `krateo-evaluation.md` |
| 11 | Esempio AI | 8, 10 | `AI-LOG.md` |

## 5. Priorità in base ai pesi

- **Must (≈75% del voto):** fasi 1, 2, 3, 4, 5 (minimo), 8 e il runbook. Analisi 18% + troubleshooting 20% + implementazione 15% + architettura 12% + automazione 10%.
- **Should:** fasi 6, 7, 10 completa.
- **Nice:** PoC Krateo, Trivy, alert avanzati, supporto OpenShift (solo come nota nel documento).

Se sei in ritardo, taglia da Nice e Should, **mai dalla fase 8**.

## 6. Rischi

| Rischio | Mitigazione |
|---|---|
| RAM insufficiente (app + Prometheus) | Aumenta le risorse di Docker; riduci repliche e retention; disattiva Alertmanager se serve |
| Modifica al frontend rompe la build | Piano B con solo redis_exporter + kube-state-metrics |
| Flux: token GitHub o permessi | Prepara il PAT prima; verifica con `flux check --pre` |
| NetworkPolicy che blocca il traffico | Applica dopo che tutto funziona e testa con `smoke-test.sh` |
| Demo dipendente dalla rete | Immagini pre-importate in k3d, prova offline |
| Documenti non allineati al codice | Esegui ogni comando dei doc almeno una volta prima della consegna |
| Segreti nei prompt o nel repo | Mai token, chiavi age private o `.env` nei prompt; `.gitignore` e controllo prima di ogni push |

## 7. Definition of done finale

- [ ] Tutti i deliverable della sezione 8 della traccia presenti nel repo.
- [ ] Demo completa eseguita da zero senza interventi non documentati.
- [ ] `AI-LOG.md` e `docs/ai-usage.md` coerenti, con almeno un caso di troubleshooting.
- [ ] Nessun secret in chiaro nel repo (storia git inclusa).
- [ ] Ogni scelta spiegabile in 2 frasi con il relativo trade-off.
