# Checklist della demo

I comandi sono quelli eseguiti nelle due prove generali del 2026-11-24 (cluster cancellato e ricreato ogni volta). I tempi sono **misurati con l'orologio di questa macchina** (Docker con 6 CPU, circa 9,7 GiB, rete di casa); su un'altra macchina o rete cambiano. Dove un passo non è stato cronometrato lo dico.

Tutti i comandi partono dalla radice del repository. `kubectl` e `flux` usano `--context k3d-boutique` perché su questa macchina esistono altri cluster.

## 0. Prima di iniziare (non cronometrato)

```bash
docker info >/dev/null && echo "docker ok"
gh auth status                          # serve per il bootstrap di Flux
ls ~/.config/sops/age/keys.txt          # la chiave age (privata) deve esserci
git checkout main && git pull
```

Chiudi le pagine di Grafana che non servono: con molte query aperte saturano la CPU ([observability.md](observability.md) §8).

## 1. Percorso e tempi

Le colonne sono le due prove complete da cluster distrutto. «Tempo» è dall'avvio del passo; la riga «Totale» è dall'inizio della prova.

| # | Passo della demo | Comando | Prova 1 | Prova 2 |
|---|---|---|---|---|
| 1 | Struttura del repository | `tree -L 2 -d` e [README](../l2-challenge/README.md) | non cronometrato | non cronometrato |
| 2 | Build dell'immagine | vedi sotto | non cronometrato | non cronometrato |
| 3a | Cancellare il cluster | `k3d cluster delete boutique` | 1 s | 2 s |
| 3b | Creare il cluster | `scripts/cluster-up.sh` | 56 s | 67 s |
| 3c | Installare Flux | `GITHUB_TOKEN="$(gh auth token)" scripts/flux-bootstrap.sh` | 35 s | 49 s |
| 3d | Tutte le Kustomization `Ready` | `flux --context k3d-boutique get kustomizations` | circa 2 min 25 s dopo il bootstrap | circa 3 min dopo il bootstrap |
| | **Totale: da cluster distrutto a shop funzionante** | | **circa 4 min** | **circa 5 min** |
| 4 | Pod, service, ingress, configurazione | `scripts/ops.sh status` | 2 s | — |
| 5 | Endpoint principali | `scripts/smoke-test.sh` (dev), poi con `http://boutique-prod.localtest.me:8080` (prod) | 7/7 dev e prod, 3 s | 7/7 dev e prod, 4 s |
| 6 | Health, log, metriche | `scripts/ops.sh grafana`, poi `scripts/ops.sh -n dev logs frontend --tail 5` | Grafana `/api/health` 200 | Grafana `/api/health` 200 |
| 7 | Aggiornamento e rollout | PR → CI → Flux ([ci.md](ci.md)) | non rifatto: CI 2 min 41 s – 3 min 18 s (ultime tre esecuzioni, da `gh run list`) più circa 40-55 s di Flux | non rifatto |
| 8 | Guasto | `scripts/break-it.sh image-tag` | guasto in 3 s, sintomo visibile entro 25 s | non rifatto |
| 8 | Ripristino | `scripts/break-it.sh restore` | 10 s, smoke test 7/7 | non rifatto |
| 9 | Rollback | vedi §3 | misurato il 2026-11-24 prima delle prove ([runbook.md](runbook.md) §4) | non rifatto |
| 10 | Krateo | [krateo-evaluation.md](krateo-evaluation.md), [ADR 0005](adr/0005-krateo-non-adottare-ora.md) | solo da raccontare | — |
| 11 | Uso dell'AI | [ai-usage.md](../l2-challenge/ai-usage.md), [AI-LOG.md](../AI-LOG.md) | solo da raccontare | — |

Prova 1 comprende anche `scripts/netpol-test.sh` (75 s, tutte le NetworkPolicy verificate come bloccanti): non è nel percorso della demo, ma è il modo di mostrare la sicurezza di rete.

**Passo 2, build.** Il build di tutti gli 11 servizi avviene in CI, non a mano ([ci.md](ci.md)). Per mostrarlo: `gh run list --workflow release --limit 3`. Per l'immagine del frontend in locale: `docker buildx build --platform linux/arm64 -t boutique/frontend:demo --load src/frontend`. Nessuno dei due è stato cronometrato nelle prove generali.

**Passo 7, aggiornamento.** Il tempo dal merge al rollout in dev è dominato dalla CI (build di 11 servizi per 2 architetture): le ultime tre esecuzioni di `release` su GitHub sono durate da 2 min 41 s a 3 min 18 s, e sono tutte del 2026-11-20 (nessuna esecuzione nuova in queste prove, perché non ho toccato `src/`). **Non ho rifatto l'intero ciclo PR → CI → rollout** nelle prove generali. La parte di Flux, dal commit su `main` al Deployment aggiornato, è di circa 40-55 s (misurata il 2026-11-19 e il 2026-11-24). Il totale atteso è quindi di circa 4 minuti, **somma di due misure separate, non misurato di seguito**. Per non aspettare la CI durante la demo conviene raccontarla e mostrare l'ultima esecuzione.

## 2. Cosa è andato storto nelle prove

- **Riavvii a freddo (prova 2).** Tre pod (`emailservice`, e `recommendationservice` in dev e in prod) hanno avuto **un riavvio** ciascuno, codice 137, causa «Liveness probe failed: timeout … within 1s». Nella prova 1 non c'è stato nessun riavvio. La mia ipotesi è la contesa di CPU all'avvio, quando il nodo crea insieme dev, prod e lo stack di osservabilità; **non l'ho provata**. Conseguenza per la demo: dopo il bootstrap, `RESTARTS` di questi pod può essere 1 senza che sia un guasto. Se si vuole mostrare uno zero pulito, aspettare qualche minuto non basta: il contatore non si azzera.
- **Dipendenze di Flux.** Nei primi minuti `observability-config` e `observability-stack` sono `False` con «dependency … is not ready»: è l'ordine `dependsOn`, normale. Lo stesso si è visto dopo lo stop e il riavvio del cluster, e si è risolto da solo in circa 2,5 minuti.
- **Il job `helm-install-traefik`** compare `Completed` con 1 o 2 riavvii: è il job di installazione di k3s, non un'anomalia dell'app.
- **Password di Grafana.** `scripts/ops.sh grafana` la stampa in chiaro: non farlo con lo schermo condiviso; usare `scripts/ops.sh grafana --copy`.

**Le due prove generali sono state fatte prima della promozione a prod del 2026-11-24** (PR #23): in entrambe prod era a `prod@7a723188` e i suoi target Prometheus erano `down`, cosa che i tempi della tabella non mostrano. Dopo la promozione un cluster nuovo parte con prod a `prod@c2af201e` e i target `up`; **questo non è stato provato con un cluster ricreato**, solo con il cluster già in esecuzione (target `up` circa 50 s dopo l'applicazione di Flux). Un terzo giro da cluster distrutto lo confermerebbe.

## 3. Rollback (passo 9)

Il rollback richiede un commit sbagliato su `main`, quindi due PR. Sequenza provata il 2026-11-24 e **ordine corretto** (quello provato aveva un errore di ordine, descritto in [runbook.md](runbook.md) §4):

1. Commit volutamente sbagliato su `main` (per esempio un tag inesistente del frontend in `deploy/components/dev-images/kustomization.yaml`); dopo circa 40 s Flux lo applica: nuovo pod `ImagePullBackOff`, vecchio pod in servizio, shop ancora `200`.
2. Tampone: `flux suspend kustomization boutique-dev`, poi `kubectl --context k3d-boutique -n boutique-dev rollout undo deploy/frontend` (1 s).
3. `git revert -m 1 <merge>` su un branch, PR, merge.
4. `flux reconcile source git flux-system`, controllare con `flux get sources git` che la revisione sia quella del revert, **poi** `flux resume kustomization boutique-dev`.
5. `scripts/smoke-test.sh`.

Il punto 4 nell'ordine indicato **non è stato misurato**: nella prova ho ripreso Flux troppo presto e il ripristino è durato circa 5 minuti. Per questo conviene fare una prova a parte prima della demo. In demo, se i tempi stringono, raccontare l'esito invece di rifarlo dal vivo.

## 4. Piano B se manca la rete

Quello che **ho provato**: tutte le 25 immagini del cluster hanno `imagePullPolicy: IfNotPresent` e restano nel nodo k3d. `k3d cluster stop boutique` seguito da `k3d cluster start boutique --wait` ha riportato lo shop su in 72 s dall'avvio dello stop (21 s stop, 16 s start più l'attesa dei pod), con dev e prod `Ready` e **nessun nuovo pull di immagini** dopo il riavvio. Il cluster mantiene quindi lo stato senza internet.

Cosa ne segue, per ragionamento e **non per prova**:

- **Non cancellare il cluster prima di una demo senza rete.** Il passo 3 (cancellare e ricreare) richiede GitHub per Flux e il registro GHCR (e quay.io per lo stack) per le immagini: senza rete fallisce.
- I passi 7 e 9 (commit, PR, riconciliazione) richiedono GitHub: senza rete si raccontano mostrando l'esito già registrato nel runbook.
- I passi 4, 5, 6 e 8 lavorano solo sul cluster locale; `break-it.sh` non tocca Git.

**Non provato:** la demo con la rete davvero staccata, e `k3d image import` per pre-caricare le immagini in un cluster nuovo. Prima di contare su questo piano serve una prova con il Wi-Fi spento.

## 5. Dopo la demo

```bash
scripts/break-it.sh status       # niente deve restare guasto o sospeso
flux --context k3d-boutique get kustomizations
```

`break-it.sh` sospende la Kustomization di dev: se non si esegue `restore`, Flux resta fermo.
