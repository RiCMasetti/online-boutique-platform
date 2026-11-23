# Runbook: diagnosi e ripristino in dev

Tutto quello che è scritto come «misurato» è stato eseguito il 23 novembre 2026 su dev (k3d, un nodo, 12 Deployment) con `scripts/break-it.sh`. Quello che non ho provato è segnato come tale.

## 1. Controllo rapido (30 secondi)

```bash
scripts/smoke-test.sh                       # home, prodotto, carrello, checkout: 7 controlli
kubectl -n boutique-dev get pods            # tutti 1/1 (redis-cart 2/2) e Running?
flux get kustomization boutique-dev         # READY True, revisione attesa, SUSPENDED False
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090   # poi /alerts
```

Attenzione: **`Ready` non basta**. Le probe non guardano le dipendenze (vedi `docs/architecture.md` §4): un frontend con un backend sbagliato è `Ready` e risponde 500. Si guarda anche il codice di risposta dello shop e gli alert.

## 2. Albero di diagnosi

```
Lo shop risponde?
├─ No (502/503 dall'Ingress)
│   └─ kubectl get deploy frontend: repliche 0/0 o 0/1?
│       ├─ 0/0  → qualcuno ha scalato a mano (§3.5)
│       └─ 0/1  → kubectl describe pod: ImagePullBackOff (§3.1), CrashLoopBackOff (§3.3), OOMKilled (§3.4)
├─ Sì, ma pagine in 500
│   └─ kubectl logs deploy/frontend: "name resolver error" / "connection refused" → indirizzo di un backend (§3.2)
│      se il backend è Redis (carrello) → docs/observability.md §8, alert RedisDown
└─ Sì, tutto 200 ma un rollout non finisce / un pod è in errore
    └─ kubectl rollout status deploy/<nome>: il vecchio pod resta in servizio, gli utenti non vedono nulla.
       Nuovo pod in errore → §3.1, §3.3, §3.4
```

Comandi di base, in quest'ordine:

```bash
kubectl -n boutique-dev get pods
kubectl -n boutique-dev describe pod <pod>              # State, Last State (Reason, Exit Code), Events
kubectl -n boutique-dev logs <pod> --previous           # log dell'istanza morta, non di quella nuova
kubectl -n boutique-dev get events --sort-by=.lastTimestamp | tail -20
kubectl -n boutique-dev rollout status deploy/<nome>
kubectl -n boutique-dev rollout history deploy/<nome>
```

## 3. Scenari provati

`scripts/break-it.sh <scenario>` sospende la Kustomization Flux di dev e modifica il cluster con `kubectl`; `scripts/break-it.sh restore` riprende Flux, riapplica lo stato di Git, reimposta le repliche e **fallisce** se un Deployment non è pronto. Il ripristino misurato è di 6-21 secondi.

I tempi di diagnosi non li ho misurati in modo onesto: i guasti li avevo scelti io e sapevo la risposta. Il criterio «rompere e riparare in meno di 5 minuti» è soddisfatto per il ripristino; per la diagnosi vale solo se si segue questa guida, e andrebbe provato da qualcun altro.

### 3.1 `image-tag`: tag di immagine inesistente

- **Sintomo.** `kubectl get pods`: nuovo pod `ImagePullBackOff` (dopo circa 30 s), vecchio pod `Running`. `rollout status` non finisce. **Lo shop continua a rispondere 200**: il rolling update tiene il vecchio pod finché il nuovo non è pronto.
- **Ipotesi.** Tag sbagliato, registro irraggiungibile, immagine privata senza credenziali.
- **Diagnosi.** `describe pod` e gli eventi: `Failed to pull image "…/frontend:tag-che-non-esiste": … NotFound`. `NotFound` indica un tag che non esiste; un errore di rete o `unauthorized` indicherebbe altro.
- **Causa.** Tag inesistente nel Deployment.
- **Fix.** Ripristino dello stato di Git (`restore`). In una situazione reale il tag sbagliato sta in Git: vedi §4.
- **Verifica.** Il pod nuovo `Running`, `smoke-test.sh` verde. Misurato: ripristino 7 s.
- **Alert.** Nessuno osservato, e non me lo aspettavo: il frontend resta disponibile. Il vero segnale è il rollout bloccato.

### 3.2 `bad-addr`: indirizzo di un backend sbagliato

- **Sintomo.** Pod `Running` e `Ready`, `/_healthz` 200, `/cart` 200, **`/` e `/product/...` 500**. Zero riavvii.
- **Ipotesi.** Backend giù, DNS, indirizzo sbagliato.
- **Diagnosi.** `kubectl logs deploy/frontend`: `could not retrieve product: rpc error: code = Unavailable desc = name resolver error: produced zero addresses`. Poi confronto con `kubectl get deploy frontend -o jsonpath='{.spec.template.spec.containers[0].env}'` e con `kubectl get svc`: il Service indicato non esiste.
- **Causa.** `PRODUCT_CATALOG_SERVICE_ADDR` punta a un Service inesistente. I client gRPC sono *lazy* (`grpc.NewClient`): il frontend parte lo stesso e l'errore si vede a ogni richiesta, non all'avvio.
- **Fix e verifica.** `restore`; `smoke-test.sh`. Misurato: ripristino 21 s.
- **Alert.** `FrontendHigh5xxRate`: `pending` tra +55 s e +85 s dal guasto, `firing` tra +2 min 55 s e +3 min 25 s (campioni ogni 30 s). I tempi sono con il nodo poco carico.

### 3.3 `missing-addr`: variabile mancante

- **Sintomo.** Il nuovo pod di `checkoutservice` va in `CrashLoopBackOff` (dopo circa 75 s: 3 riavvii), il vecchio resta in servizio, **il checkout continua a funzionare** (smoke test verde durante il guasto).
- **Diagnosi.** `logs <pod> --previous`: `panic: environment variable "SHIPPING_SERVICE_ADDR" not set` con stack in `main.mustMapEnv`. `describe`: `Last State: Terminated, Reason: Error, Exit Code: 2`.
- **Causa.** Variabile assente: `mustMapEnv` fa `panic`. Con un valore sbagliato ma non vuoto non si avrebbe crash loop (§3.2).
- **Fix e verifica.** `restore`. Misurato: 6 s.
- **Alert.** `PodCrashLooping`: `pending` entro 30 s, `firing` tra +2 min 31 s e +3 min 01 s (`for: 2m`). Dopo il ripristino era ancora `firing` 20 s dopo: la serie sparisce al giro di raccolta successivo; non ho misurato il momento esatto del rientro.

### 3.4 `low-memory`: limite di memoria troppo basso

- **Sintomo.** Nuovo pod di `currencyservice` in `CrashLoopBackOff` (3 riavvii in circa 60 s); vecchio pod in servizio; shop 200.
- **Diagnosi.** `describe pod`: `Last State: Terminated, Reason: OOMKilled, Exit Code: 137`. Il log dell'istanza uccisa si ferma a `Profiler disabled.`: l'OOMKill non lascia messaggi nel log, **l'unico indizio è nello stato del container**. Eventi: `Readiness probe failed … context deadline exceeded`.
- **Ipotesi da non confondere.** Exit 137 vuol dire SIGKILL, ma può essere anche una liveness fallita (è il caso di Grafana, vedi `docs/observability.md` §8). Si distingue dal campo `Reason`: `OOMKilled` oppure `Error`.
- **Causa.** Limite di 16Mi: il processo Node di `currencyservice` ne usa circa 36Mi a regime.
- **Nota.** Con solo `--limits=memory=16Mi` l'API rifiuta la modifica (`requests` 64Mi maggiore del limite); lo script imposta anche la richiesta.
- **Fix e verifica.** `restore`. Misurato: 8 s. **Alert non osservato** in questo scenario.

### 3.5 `frontend-down`: nessuna replica

- **Sintomo.** Shop 503 (502 nei primi secondi); `get deploy frontend` mostra `0/0`; `get endpoints frontend` vuoto.
- **Causa.** Deployment scalato a 0.
- **Alert.** `FrontendUnavailable`: `pending` a +30 s, `firing` tra +1 min e +1 min 30 s (`for: 1m`).
- **Fix.** `kubectl scale deploy/frontend --replicas=1`. **Un `flux reconcile` non basta**: Git non dichiara `replicas` per il frontend, il campo non risulta tra quelli gestiti da `kustomize-controller` e Flux non lo corregge. L'ho scoperto perché il mio primo `restore` aveva dichiarato il ripristino con il frontend ancora a 0 (shop 503 per circa 3 minuti dopo); ora lo script reimposta le repliche e verifica.
- **Verifica.** `smoke-test.sh`. Misurato: 18 s.

### 3.6 Non provato

- NetworkPolicy troppo restrittiva (scenario opzionale del piano): non eseguito.
- Guasto di Redis: provato in fase 7 con `kubectl scale`, vedi `docs/observability.md` §8.
- Più guasti insieme, e guasti con il carico reale di una demo.

## 4. Rollback GitOps

Il ripristino di §3 funziona perché **lo stato buono è in Git** e il guasto era solo nel cluster. Il caso reale è il contrario: un commit sbagliato su `main` (dev) o `prod` e Flux lo ha applicato.

| | `git revert` + PR | `kubectl rollout undo` |
|---|---|---|
| Dove sta la correzione | In Git: Flux la applica | Solo nel cluster |
| Dura nel tempo | Sì | **No**: al giro successivo di Flux (intervallo 10 min) lo stato di Git, quello sbagliato, torna |
| Traccia e revisione | Commit e PR | Nessuna |

Procedura consigliata:

1. Se serve tamponare subito: `flux suspend kustomization boutique-dev`, poi `kubectl rollout undo deploy/<nome>`. Si guadagna tempo, ma finché Flux è sospesa il cluster non segue Git.
2. `git revert <commit>` su un branch, PR, merge. Dev segue `main`; prod si aggiorna solo con la PR `main → prod`.
3. `flux reconcile source git flux-system` e `flux reconcile kustomization <nome> --with-source`.
4. `flux resume kustomization boutique-dev`. **Non dimenticarlo**: una Kustomization sospesa non segnala nulla da sola; `scripts/break-it.sh status` lo mostra.
5. `scripts/smoke-test.sh` e controllo degli alert.

**Stato della prova.** Provato: che Flux annulla una modifica manuale (fatto dal `restore`) e che non annulla i campi che Git non dichiara (§3.5). **Non provato**: `git revert` di un commit sbagliato già applicato e `rollout undo` annullato da Flux. Sono due prove che richiedono di mettere su `main` un commit volutamente sbagliato; la tabella sopra è il comportamento atteso dalla documentazione di Flux, non una misura.

## 5. Quando passare a qualcun altro

- Il ripristino a stato di Git non basta, oppure il guasto torna dopo `restore`: la causa è in Git.
- Più di un servizio coinvolto, o Redis non risponde (il carrello si perde: `redis-cart` non ha persistenza, vedi `docs/security.md`).
- Il nodo è saturo (`kubectl top nodes` oltre l'80% di CPU): prima di cercare un guasto applicativo si guarda chi consuma (`kubectl top pod -A --containers`). È già successo con Grafana.
- Prod: ogni intervento passa da Git e da una PR, mai da `kubectl`.
