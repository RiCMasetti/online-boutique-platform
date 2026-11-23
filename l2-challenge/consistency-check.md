# Controllo di coerenza dei documenti (fase 10)

Obiettivo del piano: **nessun comando nei documenti che non sia stato eseguito.** Eseguito il 2026-11-23 sul cluster in esecuzione, da Claude Code su mia richiesta; **le conclusioni sono sue, non una mia rilettura**: vanno riviste prima di fidarsene.

## Metodo e limiti

- Ho cercato i comandi nei blocchi di codice e nei comandi in linea di README, `docs/gitops.md`, `docs/observability.md`, `docs/runbook.md`, `docs/ci.md`, `docs/security.md` e `.github/workflows/README.md`.
- Per ciascuno ho cercato una prova. Gradi: **oggi** (eseguito durante questo controllo), **fase N** (eseguito prima e annotato in `AI-LOG.md`, non rieseguito), **solo CI** (gira in GitHub Actions), **no** (nessuna prova).
- «Eseguito» non significa «provato da zero»: i comandi sono girati su un cluster già avviato, tranne dove indicato.
- Non ho controllato i documenti che non descrivono questa piattaforma (vedi sotto). Non ho controllato le ancore dei link, solo l'esistenza dei file.

## Comandi

| Comando | Documento | Prova |
|---|---|---|
| `scripts/smoke-test.sh` (dev e prod) | README, runbook | **oggi**: 7/7 in entrambi |
| `kubectl … get pods` | README, runbook | **oggi**: dev 12/12 `Running` |
| `flux get kustomizations`, `flux get sources git`, `flux get kustomization boutique-dev` | README, gitops, runbook | **oggi** |
| `flux logs --kind=Kustomization --name=boutique-dev` | gitops | **oggi**: risponde; non provato con un errore da leggere |
| `kubectl … rollout history deploy/frontend` | runbook | **oggi** |
| `scripts/break-it.sh status` | README, runbook | **oggi**; gli scenari e `restore`: **fase 8** (2026-11-23, tutti e cinque) |
| `kustomize build` + `kubeconform -strict -skip Secret …` (dev, prod) | README | **oggi**: 0 invalidi (50 e 47 risorse valide); anche **solo CI** |
| `scripts/cluster-up.sh` | README, gitops | **fase 2 e 3**, da cluster cancellato (2026-11-19); **rieseguito da cluster cancellato il 2026-11-23** (nodo e Traefik pronti) |
| `scripts/apply-local.sh dev|prod` | README, security | **fase 3**, da cluster cancellato (2026-11-19, mia conferma in `AI-LOG.md`) |
| `scripts/netpol-test.sh` | README, security | **fase 3** (dev e prod, con controlli negativi); non rieseguito oggi; sintassi `bash -n` ok |
| `scripts/flux-bootstrap.sh` | README, gitops | **fase 4**: eseguito e rieseguito (idempotente) su un cluster che esisteva già; **da cluster cancellato: sì, 2026-11-23** (Secret `sops-age` creato, deploy key sostituita, nessun commit generato) |
| `gh pr create --base prod --head main`, `gh pr merge` | gitops | **fase 4/6** (PR #1, #7) |
| `git revert` e push (dev) | gitops, runbook | **fase 4**: provato con un cambio di repliche. Un commit sbagliato su prod: **no** |
| `flux suspend/resume kustomization` | gitops, runbook | **fase 8**, dentro `break-it.sh` |
| `flux reconcile kustomization … --with-source` | gitops, runbook | **fase 8**, dentro `break-it.sh restore` |
| `flux reconcile source git flux-system` | runbook | **no** (non eseguito da solo) |
| `kubectl rollout undo` contro Flux | gitops, runbook | **no**: dichiarato non provato nei due documenti |
| `docker buildx build --platform linux/arm64 … --load .` (frontend) | README, observability | **fase 5** (2026-11-20); in CI gira il build di tutti i servizi |
| `docker run … --read-only --user 1000:1000 --cap-drop ALL …` | observability | **fase 5** |
| `go test ./...` (frontend, productcatalog, shipping, checkout) | README, ci | **fase 6**, in locale e in CI |
| `dotnet test src/cartservice/` | README, ci | **solo CI** |
| `kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090` | README, runbook, observability | nome del Service verificato **oggi**; port-forward usato in fase 7 per le query |
| `kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093` | observability | nome del Service verificato **oggi**; l'inoltro e la ricezione degli alert **no** (già dichiarata «non esercitata») |
| `kubectl … get secret grafana-admin -o jsonpath='{.data.admin-password}' \| base64 -d` | observability | chiave `admin-password` presente (verificato **oggi** senza leggerne il valore); la decodifica **no** |
| `sops -d observability/stack/grafana-admin.enc.yaml` | observability | **no** (serve la mia chiave privata, non l'ho usata) |
| `sops --encrypt --filename-override …` | security | **fase 3** (creazione dei Secret esistenti) |
| `http://grafana.localtest.me:8080/api/health` | README | **oggi**: 200 |

## Documenti con comandi non verificati

Non descrivono questa piattaforma: sono dell'applicazione originale (primi commit di autori Google, tra il 2020 e il 2025) e non sono stati scritti né provati per questo fork.

| Documento | Cosa contiene |
|---|---|
| `docs/development-guide.md` | sviluppo locale con Skaffold, `minikube`/`kind`, `gcloud` |
| `docs/cloudshell-tutorial.md`, `docs/deploystack.md` | deploy su GKE da Cloud Shell |
| `docs/adding-new-microservice.md` | linee guida upstream |
| `docs/product-requirements.md`, `docs/purpose.md` | scopo del progetto upstream |
| `docs/releasing/` | processo di rilascio di Google |

**Decisione:** lasciati dove sono, per non riscrivere la cronologia, e dichiarati upstream nel [README](README.md#perché-online-boutique). **Un lettore che li apre trova comandi che nessuno ha eseguito su questa piattaforma**; se vanno tolti dalla consegna è una decisione da prendere.

## Incoerenze trovate e corrette

| Dove | Problema | Correzione |
|---|---|---|
| `README.md` (radice) | era il README di Google: Quickstart GKE, nulla sulla piattaforma | ridotto a un rimando a `l2-challenge/` più l'attribuzione |
| `.github/workflows/README.md` | elencava `ci-pr.yaml` e `ci-main.yaml` (sostituiti) e diceva che la CI sarebbe arrivata in fase 6 | riscritto sui cinque workflow reali |
| `.sops.yaml` | il commento rimandava a «README, sezione segreti», che non esisteva | rimanda a `l2-challenge/README.md`, sezione Segreti |
| `docs/architecture.md` | apriva con «nulla è stato ancora osservato a runtime»; tre voci di «Da verificare a runtime» già provate erano rimaste aperte | introduzione corretta; voci su `*_SERVICE_ADDR` e NetworkPolicy spuntate con la prova; la voce su Redis fermo resta aperta con la nota di cosa è stato visto |
| `docs/observability.md` | due sezioni «8»; la prima («Ancora da fare in fase 5») descriveva lavoro già fatto; l'apertura diceva che Prometheus «arriva in fase 7» | rinominata la prima sezione, aggiornata l'apertura |
| `docs/gitops.md` §4 | «`rollout undo` … lo si verifica nella fase 8»: in fase 8 non è stato provato | corretto in «non provato, nemmeno in fase 8» |
| `docs/security.md` §3 | «quando arriveranno Prometheus e gli exporter servirà aprire l'ingresso»: già fatto in fase 7 | aggiornato, con la nota sui target di prod |

## Incoerenze trovate e non corrette

- **`docs/security.md` §3:** «k3s non cifra i Secret a riposo (da verificare nella documentazione di k3s prima di affermarlo nel documento finale)». Non l'ho verificato: l'affermazione resta come ipotesi.
- **Comandi senza `--context`.** `docs/runbook.md`, `docs/observability.md` e parte di `docs/gitops.md` usano `kubectl` senza `--context`, mentre `gitops.md` §5 dice di usarlo sempre. Su questa macchina esistono altri contesti Kubernetes (ne ho visti due di EKS): se il contesto corrente non è `k3d-boutique`, quei comandi agiscono su un altro cluster. Gli script dello shell (`break-it.sh`, `netpol-test.sh`) hanno la guardia; i comandi a mano nei documenti no. Nel README ho messo `--context k3d-boutique` dove ho potuto; nei documenti no.
- **`docs/gitops.md` §6 e `docs/runbook.md` §4** descrivono lo stesso rollback con parole diverse («provato in dev» contro «non provato»): sono due prove diverse (revert di un cambio di repliche; revert di un commit sbagliato su prod), ma un lettore non lo capisce senza leggere entrambe.
- **Intervallo di riconciliazione:** `gitops.md` dice «ogni minuto» per il repository e «al più 10 minuti» per la Kustomization; è coerente con la configurazione ma non l'ho rimisurato.
- Le ancore dei link interni (`#…`) non sono state controllate.

## Altre note del controllo

- **Il cluster era in transizione durante il controllo.** Dopo il merge delle PR #11 e #12, `boutique-dev` e `observability-config` sono passate per alcuni minuti in `READY False` («dependency … is not up to date»), poi sono rientrate: normale riconciliazione di Flux a un nuovo commit su `main`, non un guasto. Lo dico perché i numeri di revisione citati nei documenti (`main@649735c2`, `prod@7a723188`) sono una fotografia: oggi `main` è a `6b425017`.
- **Prod resta a `prod@7a723188`**, indietro rispetto a `main`: non ho aperto la PR di promozione.
- **La prova da zero con Flux è stata fatta il 2026-11-23, dopo questo controllo** (cluster cancellato e ricreato con `cluster-up.sh` + `flux-bootstrap.sh`; 6 Kustomization `Ready` in circa 3 minuti, 30 pod `Running` con 0 riavvii, smoke test 7/7 in dev e prod). Resta non fatto il rollback di un commit sbagliato. Restano anche non provati: il percorso di un altro utente, `netpol-test.sh` sul cluster nuovo e il login a Grafana (verificato solo `/api/health`).
