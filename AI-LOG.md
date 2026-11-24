# AI-LOG — Diario di utilizzo dell'AI

Registro vivo, aggiornato **mentre si lavora** (non ricostruito a posteriori). Alimenta la sezione finale `docs/ai-usage.md`.

## Regole d'uso

1. **Prompt significativi (circa 8-10):** riportati verbatim. Sono: analisi iniziale, 2-3 di implementazione, il caso di troubleshooting obbligatorio, 1-2 di documentazione.
2. **Uso di routine:** una riga nella tabella "Registro rapido" (obiettivo, esito, verifica).
3. **Sanitizzazione:** mai secret, token, chiavi, kubeconfig, `.env` o dati personali nei prompt. Il contesto fornito va riassunto, non incollato per intero. Prima di salvare un transcript, rileggerlo.
4. **Registrare anche ciò che è stato scartato o corretto:** mostra il giudizio critico più degli output accettati.
5. **Nessun comando eseguito senza averlo capito.** Ogni output usato ha una voce "Verifica".
6. Aree (usare come etichetta): `analisi` · `implementazione` · `operations` · `documentazione` · `governance`.

Obiettivo: 15-25 voci totali, di cui almeno **un caso di troubleshooting approfondito** (con transcript sanitizzato in `docs/ai/`).

---

## Strumenti usati

| Strumento | Modello / versione | Per cosa |
|---|---|---|
| Claude Code (estensione VS Code) | Claude Sonnet 5.5 | Analisi della traccia, piano di lavoro, documentazione (AI-01) |

---

## Template voce dettagliata

```markdown
### [AI-NN · Fase X · giorno N] Titolo breve
- **Area:** analisi | implementazione | operations | documentazione | governance
- **Strumento:**
- **Obiettivo:** quale problema volevo risolvere
- **Contesto fornito:** cosa ho dato all'AI (sanitizzato, in sintesi)
- **Prompt:** verbatim se significativo, altrimenti sintesi
- **Output (sintesi):** cosa ha proposto
- **Decisione:** accettato / modificato / scartato — e perché
- **Verifica:** come ho controllato (comando, test, lettura del .proto, doc ufficiale)
- **Limiti riscontrati:** errori, allucinazioni, parti mancanti
- **Valore:** tempo risparmiato / comprensione ottenuta
```

---

## Voci dettagliate

### [AI-01 · Fase 0 · giorno 1] Analisi della traccia e piano di lavoro
- **Area:** analisi (con una componente di documentazione: piano e template di questo log)
- **Strumento:** Claude Code (estensione VS Code), modello Claude Sonnet 5.5.
- **Obiettivo:** capire a fondo i requisiti della challenge (`Challenge_L2.pdf`), ricavarne deliverable, criteri di valutazione e rischi, e produrre un piano di lavoro a 10 giorni.
- **Contesto fornito:** il PDF della traccia (testo estratto in locale con PDFKit di macOS, perché `pdftotext` non era installato) e le mie preferenze tecniche. Nessun secret o dato sensibile.
- **Prompt (verbatim, in sequenza):**
  1. "Can you analyze the requirements pdf of the challenge available in this project?"
  2. "Ok, passiamo in italiano e dammi anche l'analisi che hai fatto nella stessa lingua."
  3. "Sì, preparami il piano di lavoro con Online Boutique. Le mie preferenze sono: k3d, kustomize, Flux, approccio Prometheus. Unico dubbio: helm o kustomize."
  4. Domande di chiarimento: cos'è Krateo; repo pubblico/privato; livello di dettaglio dei prompt in `AI-LOG.md`.
- **Output (sintesi):** sintesi dei requisiti, deliverable, passi della demo e pesi di valutazione; osservazioni sui rischi (Online Boutique senza metriche Prometheus, mapping dei componenti generici della traccia sull'app reale); `PIANO_DI_LAVORO.md` con decisioni, struttura del repo, 12 fasi, calendario e mappa demo → artefatti; `AI-LOG.md`.
- **Decisione:**
  - *Accettato:* la lettura dei requisiti e la priorità dettata dai pesi (troubleshooting 20% e analisi 18% in testa).
  - *Scelta mia, con parere dell'AI:* Kustomize come packaging dell'app (l'AI lo ha raccomandato per riuso della base upstream e integrazione nativa con Flux); k3d, Flux e Prometheus sono preferenze mie.
  - *Modificato rispetto alla prima idea:* "repo privato poi fork pubblico" era la mia proposta; l'AI ha segnalato che non è fattibile su GitHub, quindi si parte da un fork pubblico.
  - _Da completare da me:_ eventuali parti del piano che decido di cambiare o tagliare.
- **Verifica:**
  - Fatta durante la sessione: testo del PDF riletto per intero; somma dei pesi di valutazione ricontrollata (100%).
  - _Da fare e spuntare da me prima di fidarmi del piano:_
    - [x] Rileggere il PDF originale e confrontarlo con la sintesi (deliverable e passi della demo). _Fatto da me, 2026-11-19: nessuna correzione._
    - [x] Verificare nella documentazione ufficiale di Krateo che le composition si basino su chart Helm. _Fatto da me, 2026-11-19: confermati chart Helm, OCI, tgz e private registry. Fonte: https://docs.krateo.io/how-to-guides/kco-operations/deploy-composition-definition/ (indicata da me). Doppio controllo di Claude Code il 2026-11-19 con WebFetch: la pagina conferma chart Helm, OCI, `.tgz` e private registry (blocco `credentials` con `passwordRef`), e indica come prerequisito un `values.schema.json` nella root del chart. Limite: WebFetch riassume la pagina con un modello più piccolo, quindi citazioni ed esempi non sono una lettura integrale. Resta da leggere la pagina direttamente prima della fase 9._ _Riletta in fase 9, 2026-11-23: vedi AI-19._
    - [x] Verificare che k3s applichi le NetworkPolicy di default. _Confermato da me, 2026-11-19. Resta la prova pratica in fase 3: un pod bloccato da una policy deve davvero non raggiungere il servizio._
    - [x] Verificare quali servizi di Online Boutique emettono log JSON e che la base `kustomize/` upstream contenga i component indicati. _Verificato da Claude Code su richiesta mia, 2026-11-19, con lettura statica di codice e manifest (non con i log a runtime). Esito in AI-04._
    - [x] Confermare scadenza e risorse della mia macchina (RAM di Docker) prima di accettare il calendario. _Fatto da me: RAM di Docker alzata._
- **Limiti riscontrati:**
  - La descrizione di Krateo viene dalla conoscenza generale del modello, non da una verifica sulla documentazione attuale: l'AI stessa l'ha segnalato.
  - Diverse affermazioni su Online Boutique e k3s sono dichiarate "da verificare", quindi plausibili ma non provate.
  - Le stime (S/M/L e calendario) sono indicative, senza sapere quanto conosco già gli strumenti.
  - La prima risposta è arrivata in inglese; ho dovuto chiedere di passare all'italiano.
- **Valore:** comprensione rapida di un documento di 7 pagine, struttura di lavoro e priorità chiare fin dal giorno 1, e un'alternativa corretta a un'idea irrealizzabile (repo privato → fork pubblico). Il valore reale dipende però dalle verifiche in lista, non dalla sola risposta dell'AI.

---

## Registro rapido (uso di routine)

| ID | Giorno | Area | Strumento | Obiettivo | Esito (acc./mod./scart.) | Verifica |
|---|---|---|---|---|---|---|
| AI-02 | 1 | operations | Claude Code | Verificare i tool della fase 0 (versioni, presenza), risorse Docker e remote git del fork | acc. | Comandi eseguiti e output riletti: 8 tool mancanti installati da me con brew e ricontrollati; `gh repo view` conferma fork pubblico; RAM Docker alzata da me |
| AI-03 | 1 | documentazione | Claude Code | Prima bozza di `docs/adr/0001-scelte-di-progetto.md` dalla tabella del piano | acc. | Rilettura integrale da me, nessuna modifica. Le voci prima non verificate (NetworkPolicy di k3s, component upstream, log JSON) sono state verificate poi, vedi AI-01 e AI-04 |
| AI-04 | 1 | operations | Claude Code | Rimuovere i workflow upstream legati a GCP, estendere `.gitignore`, aggiungere pre-commit con gitleaks, scansionare la history | acc. | Letti i workflow prima di rimuoverli (credenziali GCP di upstream, quindi inutilizzabili su un fork); YAML residui caricati con Ruby; `gitleaks git` su 2775 commit senza leak; `pre-commit run --all-files` passato. Commit `5b171834` |
| AI-05 | 1 | analisi | Claude Code | Verificare i punti aperti di AI-01: component upstream e log JSON per servizio | mod. | Vedi sotto: ha corretto un'assunzione errata del piano |
| AI-06 | 1 | analisi | Claude Code | Mappa dei servizi e `docs/architecture.md` (diagramma, tabelle servizio/protocollo/dipendenze, punti critici) | mod. | Lettura statica di `kustomize/base`, `protos/demo.proto`, codice di frontend, checkout, cart, recommendation e policy di rete. Vedi sotto: ha corretto il piano. **Da fare da me:** rileggere `architecture.md` confrontandolo con i manifest e spuntare la lista "Da verificare a runtime" in fase 2 |
| AI-07 | 1 | operations | Claude Code | Fase 2: `cluster-up.sh`, overlay dev minimo, `smoke-test.sh`, diagnosi dei pod in crash al primo deploy | mod. | Eseguito su k3d: 12 pod `1/1 Running`, smoke test (checkout incluso) superato. Diagnosi con `describe`, `logs --previous`, `kubectl top` e `crictl inspecti`: immagini upstream solo amd64 su nodo arm64 (probe in timeout) e poi OOMKilled su cart/currency/payment. Vedi `docs/architecture.md` §10. Workaround nell'overlay dev, da rimuovere con le immagini multi-arch. Il primo `cluster-up.sh` falliva perché Traefik viene installato da k3s dopo il nodo Ready: corretto con attesa esplicita. **Da fare da me:** rileggere script e overlay prima del commit |
| AI-08 | 1 | governance | Claude Code | Confronto delle opzioni per le immagini solo amd64 e scrittura di `docs/adr/0002-immagini-multi-arch.md` | acc. | L'AI ha proposto tre opzioni (build multi-arch di tutto, solo frontend, Rosetta) e ha raccomandato la prima più un tentativo con Rosetta. **Decisione mia:** build multi-arch di tutti i servizi, per mantenere la compatibilità in ambiente di sviluppo; l'esperimento Rosetta è stato scartato. Verificato sul repo: i Dockerfile usano `TARGETARCH`; la VM è QEMU senza Rosetta. Non verificato: runner arm64 gratuiti per il fork pubblico e visibilità di default dei pacchetti GHCR (rimandati alla fase 6) |
| AI-09 | 3 | implementazione | Claude Code | Fase 3: base e overlay `dev`/`prod`, hardening, NetworkPolicy, Secret Redis con SOPS+age, `apply-local.sh` e `netpol-test.sh`, `docs/security.md` | mod. | Eseguito su k3d: dev (12 pod) e prod (13 pod) attivi, smoke test superato in entrambi, `kubeconform` valido (Secret cifrato escluso). Dettagli e correzioni sotto |
| AI-10 | 4 | implementazione | Claude Code | Fase 4: `flux bootstrap github`, Kustomization per infrastruttura, dev e prod con SOPS, `scripts/flux-bootstrap.sh`, `docs/gitops.md`, ADR 0003 | mod. | Eseguito su k3d: Flux sano, dev e prod gestiti da Flux, decifratura SOPS verificata, commit su `main` → dev aggiornato senza `kubectl apply`, rollback con `git revert`. Dettagli sotto |
| AI-11 | 5 | implementazione | Claude Code | Fase 5 (solo frontend): metriche Prometheus `/metrics`, Dockerfile, build locale arm64/amd64, `docs/observability.md` | mod. | Test Go e `docker run` con le restrizioni del pod; scoperto e corretto un bug di build multi-arch ereditato da upstream. Poi provato in k3d dopo il push su `main`: serie con il traffico del loadgenerator. Dettagli sotto |
| AI-12 | 5 | implementazione | Claude Code | Fase 5: sidecar `redis_exporter` in `redis-cart`, porta `metrics` sul Service | acc. | Provato in locale (password giusta/sbagliata), dry-run lato server, poi nel cluster dopo il push: `redis_up 1`, smoke test superato. Dettagli sotto |
| AI-13 | 5 | operations | Claude Code | Fase 5: verifica dei log JSON a runtime e delle probe, con prova di guasto (Redis spento in dev) | mod. | Log controllati riga per riga su 12 pod; guasto provato nel cluster e ripristinato; una sola correzione di configurazione (`ENV_PLATFORM`, verificata nel cluster), nessuna probe modificata. Dettagli sotto |
| AI-14 | 6 | implementazione | Claude Code | Fase 6: workflow GitHub Actions (controlli, build multi-arch su runner nativi, push GHCR, tag in dev), Dockerfile di tutti gli 11 servizi, `docs/ci.md` | mod. | Controlli eseguiti in locale; sulla PR #2 passano `checks` e le 22 build senza push. Push GHCR, manifest e rollout **non ancora eseguiti**. Dettagli sotto |
| AI-15 | 6 | operations | Claude Code | Fase 6: promozione di prod (immagini GHCR, via `arm64-workaround`) e PR `main → prod` | mod. | PR #6 e #7 unite da me (autore); Flux ha applicato `prod@7a723188`; 0 restart, smoke test ok. Eventi `Unhealthy` negli avvii. Dettagli sotto |
| AI-16 | 7 | implementazione | Claude Code | Fase 7: kube-prometheus-stack via HelmRelease, ServiceMonitor, alert, dashboard, NetworkPolicy per Prometheus, ADR 0004 | mod. | Scritto e validato in modo statico, poi installato e provato in dev: target `up`, alert scattati con Redis spento; Grafana saturava la CPU, la PR #10 non e' bastata (tornato al limite aprendo Metrics Drilldown). Dettagli sotto |
| AI-17 | 8 | operations | Claude Code | Troubleshooting di Grafana in down (incidente reale, 23 nov): l'utente ipotizza la memoria | mod. | Ipotesi dell'utente **non confermata**: era la CPU. Il fix della PR #10 non ha retto: tornato al limite aprendo Metrics Drilldown (131 POST in 2 minuti); a schede chiuse 18-130 mCPU. Causa non provata |
| AI-18 | 8 | operations | Claude Code | Fase 8: `scripts/break-it.sh` (5 guasti), `docs/runbook.md` | mod. | Tutti i guasti eseguiti e ripristinati in dev con tempi misurati. Un difetto del mio `restore` trovato provando il guasto; rollback GitOps non provato. Dettagli sotto |
| AI-19 | 9 | analisi | Claude Code | Fase 9: valutazione di Krateo, chart wrapper `krateo/boutique-environment`, ADR 0005 | mod. | Documentazione letta da me/AI dal sito (19 pagine); chart con controlli statici passati; **nulla provato in Krateo**. Dettagli sotto |
| AI-20 | 10 | documentazione | Claude Code | Fase 10: `l2-challenge/` (README, `ai-usage.md`, `consistency-check.md`), README della radice, correzione di documenti vecchi | mod. | Comandi del README rieseguiti sul cluster (smoke test, `kustomize`+`kubeconform`, `flux get`); prova da zero con Flux fatta in seguito, vedi AI-21. Dettagli sotto |
| AI-22 | 8 | operations | Claude Code | Prova del rollback GitOps in dev: commit sbagliato (PR #19), `rollout undo` contro Flux, `git revert` (PR #20) | mod. | Misurato; un mio errore di ordine (`flux resume` prima del fetch del revert) ha riapplicato il commit sbagliato. Dettagli sotto |
| AI-21 | 10 | operations | Claude Code | Cancellazione e ricreazione del cluster k3d con `cluster-up.sh` e `flux-bootstrap.sh` (prova da zero del README, percorso A) | acc. | Kustomization, pod, riavvii, smoke test dev e prod, Grafana `/api/health`, Secret SOPS. Errori miei sotto |

**AI-20, fase 10: documentazione finale (2026-11-23):**

- *Prompt (dell'utente):* «Passiamo alla fase 10, in cosa consiste? Ricordamelo»; poi la proposta di una cartella `l2-challenge` con il nuovo README; poi «procedi con l'opzione 1» (README completo in `l2-challenge/`, README della radice ridotto a un rimando).
- *Eseguito:* letti gli script, `docs/` e questo diario per scrivere `l2-challenge/README.md` e `ai-usage.md`; rieseguiti sul cluster `smoke-test.sh` (dev e prod, 7/7), `kustomize build` + `kubeconform` (0 invalidi), `flux get`, `flux logs`, `rollout history`, `break-it.sh status`, controllo dei Service e della chiave del Secret di Grafana (senza leggerne il valore); controllo dei link relativi nei documenti (3 rotti: i file che stavo ancora scrivendo).
- *Trovato:* sei documenti rimasti indietro (README dei workflow, commento di `.sops.yaml`, `architecture.md`, `observability.md`, `gitops.md`, `security.md`) e cinque punti non corretti, tra cui `--context` mancante nei comandi dei documenti e documenti upstream con comandi mai eseguiti. Dettagli in `l2-challenge/consistency-check.md`.
- *Errori miei corretti scrivendo:* (1) avevo scritto che i log JSON erano in «10 servizi su 12»: sono 9 su 11 (`docs/observability.md` §6); (2) avevo attribuito le *requests* del nodo a uno stato con lo stack acceso, ma il dato (60%/30%) era di prima dello stack: rimisurato 66% CPU e 40% memoria; (3) avevo scritto «tre rilievi accettati» per la revisione di AI-16: sono quattro accettati, uno scartato, uno riconosciuto; (4) il primo `gh pr list` ha interrogato il repository upstream di Google e non il fork: me ne sono accorto leggendo i titoli delle PR.
- *Non fatto:* la prova da zero del README con Flux su un cluster cancellato (distruttiva e scrive sul repository: da decidere con l'utente) e il percorso di un altro utente.
- *Da fare da me:* rileggere `l2-challenge/ai-usage.md` (sintesi scritta dall'AI sul proprio uso, quindi con il rischio di favorire se stessa) e decidere cosa fare dei documenti upstream.

**AI-19, fase 9: valutazione di Krateo (2026-11-23):**

- *Prompt (dell'utente):* «Passiamo alla fase 9».
- *Eseguito:* scaricate e convertite in testo 19 pagine di docs.krateo.io (3.0.0) per leggerle intere, invece di affidarsi a un riassunto di WebFetch (voce di AI-01); lette: architettura, Core Provider, CDC (workflow, status, naming, values), operazioni (deploy, create, versioni, pausa, cancellazione), installazione, note di rilascio 3.0.0, troubleshooting. Scritti `docs/krateo-evaluation.md`, `docs/adr/0005-krateo-non-adottare-ora.md` e `krateo/` (chart con `values.schema.json`, `CompositionDefinition` e `Composition` di esempio).
- *Verificato (comandi eseguiti):* `helm lint`; 8 input errati rifiutati dallo schema con `helm template`; `kubeconform -strict` con gli schemi dei CRD di Flux (2 risorse valide); le patch del chart applicate con `kustomize build` sull'overlay prod (2 repliche, limiti 200m/128Mi). Risorse del nodo da `docker info` e `kubectl top nodes`.
- *Non verificato:* tutto ciò che sta dentro Krateo (accettazione del chart, `kind` generato, permessi del CDC verso gli oggetti Flux, ordine di cancellazione). Il `kind` `BoutiqueEnvironment` e l'`apiVersion` sono dedotti da un esempio della doc, non da una regola scritta.
- *Scelte dell'AI da rivedere:* (1) "nome servizio" interpretato come nome dell'ambiente; (2) il confine "Krateo possiede gli oggetti Flux, Flux possiede l'app" è una proposta mia, non una pratica documentata; (3) la raccomandazione "non adottare ora" poggia sui requisiti dichiarati dalla doc (12 vCPU, 16 GiB), che io non ho misurato; (4) il chart punta a un overlay `environment-*` **che non esiste**: va creato prima di poter provare qualunque cosa.
- *Un'assenza che pesa:* nelle pagine lette Flux non compare mai e gli esempi usano Argo CD. L'ho trattato come rischio (R2), non come incompatibilità: le pagine che non ho letto potrebbero dirne di più.
- *Incoerenze della doc trovate:* banner 3.0.0 con quickstart che installa `3.0.0-rc1`; Kubernetes >= 1.31 nei requisiti contro >= 1.30 in installazione.
- *Valore e limite:* velocizza la lettura e dà un blueprint controllabile; il rischio è che sembri più solido di quanto sia, perché i controlli statici passano e il resto no. Per questo il documento separa «verificato» da «non verificato» (§4).
- *Da fare da me:* rileggere dal sito le tre pagine su cui poggia la raccomandazione (requisiti, `architecture`, `deploy-composition-definition`) e confermare la scelta di non fare il PoC.

**AI-18, fase 8: guasti, runbook (2026-11-23):**

- *Eseguito:* `scripts/break-it.sh` con `image-tag`, `bad-addr`, `missing-addr`, `low-memory`, `frontend-down`, `restore`, `status`. Concordato con l'utente: guasti con `kubectl` e `flux suspend`, non da Git. Ogni scenario lanciato, diagnosticato con `describe`/`logs --previous`/eventi e ripristinato; `docs/runbook.md` ne riporta sintomi, diagnosi e tempi misurati.
- *Errori trovati provando, non rileggendo:* (1) `status` segnava "non sano" tutti i pod: avevo usato un backreference in `awk`, che non lo supporta; (2) il primo `low-memory` era rifiutato dall'API (richiesta 64Mi > limite 16Mi) e lasciava Flux sospesa: aggiunti `--requests` e un `trap` che la riprende; (3) **`restore` dichiarava "completato" con il frontend ancora a 0 repliche** (shop 503): Git non dichiara `replicas` per il frontend e Flux non corregge i campi che non possiede. L'ho visto dallo smoke test, non dallo script: ora `restore` reimposta le repliche e fallisce se un Deployment non e' pronto. (4) un mio `sed -i` con sintassi GNU e' fallito su macOS (BSD) senza fermare la sequenza di comandi: me ne sono accorto solo perche' il messaggio nel codice era rimasto vecchio; ho usato Python.
- *Ipotesi del piano confermate dal vivo:* un valore sbagliato non causa crash loop (solo errori 500 con pod `Ready`); un valore assente causa `panic` e `CrashLoopBackOff`.
- *Osservazione non attesa:* con un rolling update a una replica, tag inesistente, variabile mancante e limite troppo basso **non interrompono il servizio**: il vecchio pod resta. Il segnale e' il rollout bloccato, non un alert di indisponibilita'.
- *Alert esercitati:* `FrontendHigh5xxRate`, `PodCrashLooping`, `FrontendUnavailable` scattati con i tempi del runbook. Prima delle prove, gli ultimi due erano non esercitati.
- *Limiti:* i guasti li ho scelti io e conoscevo la risposta, quindi non misurano la qualita' della diagnosi dell'AI; il rollback con `git revert` e `rollout undo` contro Flux non era provato qui; provato dopo, vedi AI-22; alert non osservati per `image-tag` e `low-memory`; `CPUThrottlingHigh` su `redis-exporter` in dev notato e non indagato.

**AI-17, caso di troubleshooting: Grafana in down (2026-11-23):**

- *Prompt (dell'utente, parola per parola):* «Grafana è down, credo per un problema di memoria, non ho indagato.»
- *Cosa ho fatto prima di rispondere:* `kubectl get pods` (121 riavvii), `describe pod`, `kubectl top`, eventi. Nessun secret nell'output.
- *Ipotesi dell'utente: sbagliata.* Memoria 281Mi su 384Mi di limite; `Exit Code 137` ma `Reason: Error`, non `OOMKilled`; CPU a 4,4 core, nodo all'86%, probe in timeout anche su altri pod. Causa: la liveness uccideva Grafana saturo di CPU.
- *Cosa era sbagliato o incompleto nel lavoro dell'AI:* (1) la fase 7 documentava Grafana come "calmo dopo il riavvio" in base a pochi minuti; il problema e' tornato e il pod e' arrivato a 121 riavvii in tre giorni; (2) dopo il merge della PR #10 ho guardato la CPU per 5 minuti e ho risposto «Grafana e' ok», chiamando «verificato» un controllo senza usare l'interfaccia: dopo circa 25 minuti era di nuovo al limite. Me l'ha fatto notare l'utente («Grafana e' giu'»); (3) l'ipotesi del sidecar delle dashboard, scritta come ipotesi, era probabilmente sbagliata o incompleta.
- *Seconda indagine:* pod `2/3`, 999 mCPU (limite 1 core), 47% di throttling; nei log 131 `POST /api/ds/query` in 2 minuti, 350 in un'ora finite con status 499 dopo 60-78 s, referer `/dashboards` e Metrics Drilldown (solo 36 dalla nostra dashboard). L'utente ha confermato di aver aperto la pagina delle metriche e che la quantita' di POST aveva saturato la CPU. Chiuse le schede: 18-130 mCPU, `3/3`, 0 richieste in circa 2 minuti.
- *Esito:* causa piu' probabile il carico di query dal browser (Metrics Drilldown); **non provata**: un'osservazione, le pagine non riaperte una alla volta (l'utente ha scelto di saltare il test); non so se spiega i tre giorni del pod precedente. Nessuna correzione ulteriore ancora applicata (opzioni: disattivare Metrics Drilldown, alzare il limite di CPU, allungare le probe).
- *Valore e limite:* l'AI ha trovato la discrepanza (CPU, non memoria) leggendo lo stato del container e poi la correlazione nei log; l'utente aveva intuito la direzione ("risorse") e ha fornito il dato decisivo (cosa aveva aperto). L'AI ha dichiarato il lavoro finito troppo presto. Senza il controllo di `Reason` e della CPU la via piu' ovvia sarebbe stata alzare il limite di memoria, che non avrebbe risolto il problema (inferenza, non provata).

**AI-16, stack di osservabilità (2026-11-20, solo lavoro statico):**

- *Eseguito:* HelmRelease di kube-prometheus-stack 93.6.0, due Kustomization Flux separate, ServiceMonitor per frontend e redis-cart, quattro alert, dashboard di 10 pannelli (JSON generato con uno script, committato solo il JSON), Secret SOPS per Grafana, aperture NetworkPolicy per Prometheus, controlli in CI.
- *Verificato:* `helm template` con i miei valori (nessun errore; Ingress, Secret e sidecar delle dashboard come previsto; nessun DaemonSet), `kustomize build`, `kubeconform` (i CRD sono saltati: senza schema), JSON valido.
- *Scelte dedotte, non provate:* niente node-exporter (mount `/` nei nodi k3d: l'ho ricordato come problema noto, non l'ho provato); componenti k3s disattivati; `dependsOn` separati perché lo stack non blocchi dev e prod (ragionamento, non un guasto visto).
- *Un errore che avrei potuto fare:* `RedisDown` con solo `redis_up == 0` non sarebbe scattato spegnendo `redis-cart` (pod ed exporter spariscono e la serie con loro). L'ho notato ripensando alla prova di AI-13; ora c'è una seconda condizione su kube-state-metrics. Idem per `FrontendUnavailable`. Da confermare con il guasto vero.
- *Revisione indipendente della PR (skill code-review, livello medio) e cosa ne ho fatto:*
  1. **Accettato, con prova:** `RedisDown` poteva produrre due alert per un solo guasto (Redis giù e pod non pronto insieme: due serie con etichette diverse). Corretto aggregando per namespace; verificato con `promtool test rules` che con la vecchia espressione scattano due alert e con la nuova uno. Il rilievo era giusto e io non ci avevo pensato.
  2. **Accettato:** il ServiceMonitor del frontend ammetteva anche `frontend-external` se fosse tornato (stessa etichetta e porta): ora si tiene solo il Service `frontend`.
  3. **Accettato:** limiti di memoria: Alertmanager 128Mi (64Mi era stretto), Grafana 384Mi, sidecar di Grafana con limite (il chart non lo mette).
  4. **Accettato:** validazione delle regole in CI con `promtool` (sintassi e test), oltre al solo JSON della dashboard.
  5. **Scartato:** "versione 93.6.0 non verificata": l'ho scaricata con `helm pull` dal repository e renderizzata. "Timeout di 5 minuti di observability-config": il timeout riguarda la sua applicazione, non l'attesa del `dependsOn`.
  6. **Riconosciuto, non corretto:** un Deployment cancellato non fa scattare `FrontendUnavailable` né `RedisDown` (nessuna serie): documentato come limite.
  Inoltre la PR era in conflitto con `main` (solo `AI-LOG.md`, dopo il merge della #8): risolto.
- *Esito nel cluster dopo il merge (verificato da me, vedi `docs/observability.md` §8):* HelmRelease installato; target di dev `up`, di prod `down` (NetworkPolicy non ancora promosse: verificato che la causa è quella); 4 regole caricate, 11 query della dashboard con dati; guasto su Redis in dev con `RedisDown` firing a +78 s e `FrontendHigh5xxRate` a +162 s, rientrati dopo il ripristino.
- *Un'ipotesi che avevo sbagliato:* avevo previsto che i problemi di risorse dello stack sarebbero stati la memoria (limiti stretti, ne ho alzati tre in revisione). Il problema vero è stato la **CPU di Grafana** (fino a 4,8 core), che avevo trascurato perché non c'era un limite: l'ha indicato l'utente ("credo che Grafana faccia andare in OOM o sovraccarichi la CPU"). Ho verificato: nessun OOMKill, ma CPU saturata e kill per liveness. Causa probabile (dashboard predefinite) non provata.
- *Limite del test sul guasto:* è avvenuto durante il picco di Grafana, quindi i tempi misurati sono un limite superiore.
- *Limiti dichiarati (valutazioni fatte prima del merge, tenute per memoria):* nulla di tutto questo era stato eseguito nel cluster: non sapevo se l'HelmRelease si installava, se i target sono `up`, se le query della dashboard restituiscono dati, né se gli alert scattano. Il "done" della fase 7 non è raggiunto.
- *Da fare da me:* leggere i valori dell'HelmRelease e le regole prima del merge; il merge installa lo stack sul nodo condiviso.
- *Esito della correzione di Grafana (2026-11-23), corretto dopo una seconda verifica:* PR #10 unita da me e applicata da Flux. Per 5 minuti Grafana è stata calma (56-250 mCPU) e l'ho dichiarata a posto: **era prematuro**. Dopo circa 25 minuti era di nuovo al limite (999 mCPU, readiness in timeout) perché era stata aperta la pagina Metrics Drilldown (131 POST `/api/ds/query` in 2 minuti). Con le schede chiuse: 18-130 mCPU, pod `3/3`. Errori miei: (1) avevo scritto che dopo il primo riavvio era «calma» (sbagliato su tre giorni); (2) ho chiamato «verificato» un controllo di 5 minuti senza usare l'interfaccia, cioè senza riprodurre l'uso che aveva causato il problema; (3) l'utente ha detto «credo problema di memoria» e ho verificato prima di rispondere: era la CPU (281 MiB su 384, exit 137 dalla liveness). Limiti: la causa non è provata (correlazione osservata una volta, le pagine non sono state riaperte una alla volta per scelta dell'utente), l'ipotesi iniziale del sidecar è ora debole, e non so se spieghi anche i tre giorni del pod precedente.

**AI-15, promozione di prod (2026-11-20):**

- *Preparato:* overlay prod con le 10 immagini GHCR nel tag già verificato in dev (`e7eaa5b8b502`), eliminato il component `arm64-workaround`, documentazione allineata. Due PR: una verso `main`, poi `main → prod` come bozza.
- *Verificato prima:* `kustomize build` di dev e prod, `kubeconform`; diff del rendering di prod prima e dopo (solo immagini, probe e limiti del workaround); diff del rendering di **ciò che prod esegue oggi** (branch `prod`) contro quello nuovo.
- *Sorpresa:* la promozione `main → prod` porta in prod anche modifiche non legate alle immagini (sidecar `redis_exporter`, porta `metrics` sul Service, `ENV_PLATFORM`), perché prod era rimasta indietro dalla fase 4. L'avevo descritta come "solo il tag"; il diff del rendering l'ha corretta. Inoltre `docs/gitops.md` diceva che la PR #1 non era stata unita, ma `prod` era già a `88fec121`: documento obsoleto, corretto.
- *Capacità:* requests al 60% di CPU e al 30% di memoria sul nodo con dev e prod accesi; il rollout di prod non dovrebbe saturarlo. Stima da `kubectl describe node`, non provata.
- *Esito dopo il merge (fatto da me, l'autore del repository):* Flux ha applicato `prod@7a723188`; 11 deployment pronti, immagini `e7eaa5b8b502`, 0 restart; smoke test superato; `/metrics` e `redis_up 1` verificati. Flux ha mostrato per qualche minuto "Reconciliation in progress" sulla revisione vecchia: all'inizio mi sembrava un blocco, era l'attesa dei controlli di salute (verificato rileggendo lo stato).
- *Non perfetto:* eventi `Unhealthy` su quasi tutti i servizi durante il rollout, anche di liveness a 1 s (adservice, emailservice, recommendationservice), senza riavvii. Il nodo era occupato da 13 pod nuovi più dev; il margine delle probe da 1 s è quello che la fase 8 metterà alla prova.
- *Limiti dichiarati:* rollback di prod con `git revert` non provato; prod osservata per pochi minuti, non a regime.

**AI-14, esito (2026-11-20, fase 6, solo lavoro locale):**

- *Eseguito:* quattro workflow (`checks`, `build-images`, `ci`, `release`), rimozione dei due workflow upstream di test, modifica dei Dockerfile di dieci servizi (via i default `amd64`), component `dev-images`, `docs/ci.md`.
- *Verificato in locale:* hadolint sugli 11 Dockerfile; `kustomize build` + `kubeconform` su dev e prod; `go test` dei quattro servizi Go; build `linux/arm64` di shippingservice e cartservice con `file` sul binario (`aarch64`); simulazione di `kustomize edit set image` su una copia del repository.
- *Errori e sorprese:*
  1. **Il piano partiva da un'ipotesi sbagliata:** avevo in mente un build multi-arch con QEMU. Leggendo i Dockerfile Python ho visto che lo stadio `builder` gira sulla piattaforma di build e viene copiato nell'immagine finale, quindi in cross-build l'immagine arm64 avrebbe avuto librerie amd64. Scelti runner nativi (`ubuntu-24.04-arm`). Ragionamento dedotto dal codice, **non provato** con un build cross-arch reale.
  2. **kubeconform bocciava il Secret SOPS** (chiave `sops` non ammessa dallo schema): non l'avevo previsto, l'ho scoperto eseguendo il controllo. Soluzione: `-skip Secret`, dichiarata nei commenti.
  3. **`go test` su checkoutservice falliva** per `go vet` su un `status.Errorf` con messaggio non costante: bug upstream, corretto con `status.Error`. Fuori dal perimetro iniziale, ma il test lo richiedeva.
  4. **`kustomize edit` cancella i commenti** dell'overlay: ho spostato il tag di dev in un component dedicato dopo averlo visto nella simulazione.
  5. **L'`images:` degli overlay aveva una voce non valida** (undici nomi separati da spazi in un solo `name`): non faceva nulla perché la base fissa già `v0.10.7`. Rimossa; rendering di dev e prod invariato (`diff` vuoto).
  6. L'installazione di `actionlint` (`go install`) è stata bloccata dal sistema di permessi; non l'ho aggirata. I workflow sono stati letti con un parser YAML, non validati con `actionlint`.
- *Esito sulla PR #2:* `checks` e tutte le 22 build (runner arm64 inclusi, build `amd64` inclusa) passate al primo tentativo, 46-161 s con cache fredda; il job `merge` è saltato come previsto.
- *Primo rilascio (run 44726672556, dopo il merge della PR #2):* un solo job fallito, adservice amd64, per un `429` di Maven Central durante `./gradlew downloadRepos` (limite di frequenza, non codice); risolto rilanciando i soli job falliti. Il Dockerfile non ha ritentativi: se si ripete, va aggiunto qualcosa. Manifest multi-arch verificato da fuori su adservice (amd64 e arm64, più le attestazioni buildx `unknown/unknown`). `update-dev` ha committato il tag `06974f96d9ae`; rollout in dev con 12 deployment pronti, 0 restart, smoke test superato, nodo arm64. Nota: ho verificato lo smoke test e i restart, non il carico.
- *Bug mio emerso al primo rilascio:* il job `scan` falliva su tutti gli 11 servizi (`could not parse reference`) perché `github.repository` ha le maiuscole e GHCR le rifiuta; negli altri job avevo già usato il minuscolo. Correzione nella PR #3. Il run restava `success` perché `scan` non è bloccante: un fallimento totale passava inosservato senza guardare i job.
- *Workaround arm64 tolto da dev* (PR dedicata); resta in prod finché prod usa le immagini upstream.
- *Dopo il merge di PR #3 e #4 (run 44731010825, tag `e7eaa5b8b502`):* `scan` funziona e trova HIGH/CRITICAL (tabella in `docs/ci.md` §4; non analizzate). Dev senza workaround: 12 deployment pronti, 0 restart, nessun OOM, smoke test superato, memoria 11-74 MiB contro limiti 128-450 MiB, con il loadgenerator attivo. Restano 15 eventi `Unhealthy` di readiness (timeout 1 s) nel momento degli avvii. Ho controllato restart ed eventi, non ho misurato la latenza né ho aumentato il traffico: la tenuta a regime e sotto più carico non è provata.
- *Cosa non ho verificato nel primo `scan`:* mi ero fermato a "verde"; è stato guardando il log che ho visto che Trivy trova davvero vulnerabilità (un job non bloccante verde non basta come prova).
- *Limiti dichiarati:* prod non è stato promosso (immagini upstream e workaround ancora lì); i pacchetti GHCR vanno resi pubblici a mano e questo non è verificabile da qui; il job `update-dev` e il controllo del pull anonimo sono testati solo per lettura.
- *Da fare da me:* leggere i workflow riga per riga prima del primo push su `main` (pubblicano pacchetti e committano su `main`); decidere se accetto il commit automatico del tag invece di una PR.

**AI-13, esito (2026-11-20, fase 5):**

- *Eseguito:* controllo che ogni riga di log (ultime 200 per pod, 12 pod di dev) sia JSON valido; lettura dell'health check di ogni servizio; prova di guasto con `kubectl scale deploy/redis-cart --replicas=0` per circa 100 s, poi ripristino a 1 e smoke test; patch `ENV_PLATFORM=local` sul frontend; `docs/observability.md` §6-7.
- *Verificato:* cartservice e loadgenerator non emettono JSON (come previsto dal codice); i campi non sono uniformi (`severity` in 9 servizi su 10, tempo come `timestamp`/`time`/`instant`); con Redis spento il frontend resta `Ready` mentre la home dà 500; il cartservice va in timeout sulla probe (non `NotServing`), viene riavviato una volta dalla liveness e torna `Ready` a Redis ancora spento.
- *Errori e sorprese:*
  1. **Ho dedotto male dal codice:** dal costruttore di `HealthCheckService` (riceve lo store Redis) avevo concluso che il cartservice controllasse Redis e avevo previsto `NotServing`. Leggendo il metodo, `Ping()` è `try { return true; }`. Poi la prova dal vivo ha mostrato un terzo comportamento (timeout), che non avevo previsto. Corretta la lettura; senza la prova avrei scritto una spiegazione falsa.
  2. **Riga non JSON nel frontend** (`fmt.Println` a ogni home), non prevista dall'analisi di fase 1, che guardava solo la configurazione di logrus. Risolta con configurazione, non con codice.
  3. In `docs/architecture.md` c'era una riga obsoleta ("Redis senza password"): la password c'è dalla fase 3. Corretta.
- *Verificato dopo il push (commit `75f89cf0`):* rollout del frontend riuscito, `ENV_PLATFORM=local` presente; 344 righe di log nel pod nuovo, 0 non JSON, con 72 richieste alla home; smoke test superato.
- *Decisione:* nessuna probe modificata; il rilevamento dei guasti passa da metriche e alert (fase 7), non da readiness che dipendono da backend condivisi. Ragionamento mio, non provato in un confronto.
- *Limiti dichiarati:* causa dei timeout del cartservice non indagata (ipotesi: saturazione per richieste appese su Redis); log controllati solo in condizioni normali, non nei percorsi di errore; `timeoutSeconds: 1` del frontend non provato sotto carico; il test ha lasciato un riavvio nel contatore del cartservice e ha azzerato i carrelli in dev; le probe vanno riverificate quando la fase 6 toglie il workaround arm64.
- *Da fare da me:* valutare se accetto "nessuna probe modificata" e se vale la pena correggere `Ping()` del cartservice o i campi dei log (fuori perimetro).

**AI-12, esito (2026-11-20, fase 5):**

- *Eseguito:* sidecar `oliver006/redis_exporter:v1.97.0` (digest dell'indice multi-arch) nel Deployment `redis-cart` e porta `metrics` (9121) sul Service, in `deploy/base/kustomization.yaml` (vale per dev e prod; prod solo con la PR `main → prod`).
- *Verificato prima del push:* exporter provato in locale contro un Redis con password: giusta → `redis_up 1`; sbagliata → `redis_up 0` con `WRONGPASS`, e `/health` risponde 200 in entrambi i casi (scelta delle probe); `kustomize build` e `kubeconform` validi; dry-run lato server accettato con Pod Security `restricted`.
- *Verificato nel cluster (commit `58d2d340`):* pod `2/2`, nessun riavvio, `redis_up 1` e metriche dalla porta del Service, smoke test con checkout intero superato.
- *Scelte:* sidecar e non deployment separato (nessuna regola nuova per la NetworkPolicy di Redis, stesso Secret, stesso ciclo di vita); password da variabile d'ambiente e non da argomento.
- *Limiti dichiarati:* guasto `redis_up 0` non provato nel cluster; Prometheus non raccoglie ancora (fase 7, servirà una regola di ingress per `monitoring` sulla 9121); il riavvio ha azzerato i carrelli in dev; blackbox exporter (opzionale) non fatto; Redis senza `maxmemory`.
- *Da fare da me:* leggere il blocco del sidecar in `deploy/base/kustomization.yaml`.

**AI-11, esito (2026-11-20, fase 5 parziale):**

- *Eseguito:* `src/frontend/metrics.go` (counter e histogram per metodo/route/codice, middleware di `mux`, `/metrics` servito prima di sessione, log e tracing), 3 test Go, dipendenza `client_golang v1.23.2`, modifiche al Dockerfile, `docs/observability.md`, voce `images:` del frontend in `deploy/overlays/dev`.
- *Verificato:* test passati; `hadolint` pulito; `docker run` con `--read-only --user 1000:1000 --cap-drop ALL` espone le serie attese con `route` a template e conta i 500; `kustomize build` e `kubeconform` validi.
- *Errori e scoperte (mie e dell'ereditato):*
  1. **Bug upstream di build multi-arch:** i default `ARG BUILDPLATFORM=linux/amd64` e `ARG TARGETARCH=amd64` annullavano buildx. L'immagine "arm64" conteneva un binario x86-64 identico a quello amd64, e il build girava in emulazione (5 minuti). L'ho notato solo perché le dimensioni delle due immagini differivano di 9 byte; l'etichetta dell'immagine diceva `linux/arm64` e non basta. Ho isolato la causa con un Dockerfile di prova. L'ADR 0002 dava per buoni i Dockerfile upstream: l'ho corretto. Presente in tutti e 12 i Dockerfile: da sistemare in fase 6.
  2. **Permessi dei file:** il repo su RicDisk ha modo `0700`; l'immagine ereditava il modo e l'utente non-root non leggeva i template (panic all'avvio). Visto solo provando `docker run` con le restrizioni del pod. Risolto con `COPY --chmod`.
  3. **`go get ...@latest` aggiornava altre dipendenze e il `go` directive:** annullato e fissata una versione di `client_golang` compatibile (diff di `go.mod` solo additivo).
  4. **La voce `images:` degli overlay è un no-op:** il `name` contiene tutti i servizi su una riga e non corrisponde a nessuna immagine; il tag effettivo viene dal manifest base. Non toccata a parte la voce del frontend; da correggere prima che la CI della fase 6 usi `kustomize edit set image`.
- *Provato dopo il push (commit `7d27ffc9`):* Flux ha applicato l'overlay dev, rollout riuscito, `/metrics` mostra le serie per route con il traffico del loadgenerator (via `port-forward`, che aggira la NetworkPolicy), nessun 5xx; il log del frontend è JSON.
- *Limiti dichiarati:* Prometheus non raccoglie ancora la metrica (fase 7); amd64 non eseguito (solo binario ispezionato); `/metrics` esposto anche dall'Ingress; la NetworkPolicy del frontend bloccherà Prometheus in fase 7; l'overlay dev dipende da un'immagine importata a mano con `k3d image import`. Restano `redis_exporter`, verifica dei log JSON e delle probe.
- *Da fare da me:* leggere `metrics.go` e il diff del Dockerfile; rivedere `docs/observability.md`.

**AI-10, esito (2026-11-19):**

- *Eseguito:* `flux bootstrap github` sul fork (token da variabile d'ambiente, ottenuto con `gh auth token`: è il token OAuth di `gh`, più ampio di un PAT dedicato; non è stato stampato né salvato). Kustomization `infrastructure`, `boutique-dev` (segue `main`) e `boutique-prod` (segue il branch `prod`), tutte con `prune` e `wait`; dev e prod con `dependsOn: infrastructure` e decifratura SOPS.
- *Verificato:* Flux decifra `redis-cart-auth` in dev e prod (48 caratteri, non `ENC[...]`); smoke test superato; commit su `main` (frontend a 2 repliche) applicato in circa 45 s senza riconciliazione forzata; `git revert` riporta a 1 replica; `flux-bootstrap.sh` rieseguito (idempotente).
- *Errori miei:* (1) ho sbagliato il nome del Secret (`redis-auth` invece di `redis-cart-auth`) e ho letto "non trovato" come un possibile fallimento prima di controllare; (2) il primo `git revert` non ha creato il commit e il successivo `git commit --amend` ha riscritto il commit di test con un messaggio da revert: il push è stato rifiutato (non fast-forward), nessun danno. Sistemato con un rebase non distruttivo e un revert corretto; un `reset --hard` era stato bloccato dal sistema di permessi; (3) il test con le repliche del frontend non dimostra la separazione dev/prod, perché prod ha già 2 repliche.
- *Scelte:* `prod` segue un branch e non un tag (ADR 0003: il fork contiene i tag upstream, che un intervallo semver selezionerebbe). Le risorse di Flux stanno in `clusters/local/*.yaml` e l'infrastruttura in `infrastructure/`, non in `clusters/local/infrastructure/` come nel piano: una sottocartella di `clusters/local` sarebbe applicata due volte dalla Kustomization `flux-system`.
- *Limiti dichiarati:* "prod solo via PR" è una convenzione, senza branch protection; bootstrap su cluster nuovo e drift da modifica manuale non provati; `infrastructure/` contiene solo il namespace `monitoring`; il Secret `sops-age` è l'unico oggetto fuori da Git; non ho riletto la documentazione di Flux su build/decifratura (prova empirica).
- *Da fare da me:* rileggere `scripts/flux-bootstrap.sh` e le Kustomization/GitRepository in `clusters/local/`; ripetere da zero (`k3d cluster delete boutique`, `cluster-up.sh`, `flux-bootstrap.sh`) e decidere sul PAT dedicato al posto del token di `gh`.

**AI-09, esito (2026-11-19):**

- *Verificato prima di scrivere:* nessun servizio usa l'API Kubernetes (quindi `automountServiceAccountToken: false` è sicuro); la base ha già `runAsNonRoot`, `readOnlyRootFilesystem`, `drop ALL`, `allowPrivilegeEscalation: false`; manca solo `seccompProfile`, aggiunto. Pod Security `restricted` provato in dry-run lato server prima di attivarlo.
- *Errori miei corretti lungo la strada:*
  1. In prod restavano un ServiceAccount e una NetworkPolicy orfani del loadgenerator (il component upstream toglie solo il Deployment): rimossi con patch.
  2. `netpol-test.sh` contava come "bloccato" qualunque errore, anche un pod non creato: i casi negativi passavano per il motivo sbagliato. Corretto: il pod deve stampare `rc=N`, altrimenti è un errore. Altri due difetti nello stesso script: `kubectl run --overrides` sostituisce l'intero container (comando incluso) e `run --rm -i` perde l'output per una race.
  3. In prod il test usava la label `loadgenerator`, la cui policy non esiste: il pod era bloccato in uscita dal `deny-all`. Sorgente dei casi negativi cambiata in `emailservice`.
- *Controlli negativi sulle policy:* senza la policy di cartservice i percorsi leciti si bloccano; senza `deny-all` e senza quella policy, `emailservice` e un pod dell'altro ambiente raggiungono cartservice. Il test fallisce nei due casi, quindi rileva i cambi in entrambe le direzioni.
- *Segreti:* chiave age generata in locale (`~/.config/sops/age/keys.txt`, permessi 600, fuori dal repo); password casuali cifrate senza mai passare dall'output; `.sops.yaml` contiene solo la chiave pubblica. Nessun valore segreto è entrato in prompt, log o repo.
- *Limiti:* l'uscita di rete non è limitata (upstream `egress: [{}]`); `kustomize build` include il Secret cifrato, quindi `kubectl apply -k` non è utilizzabile finché non c'è Flux (da qui `apply-local.sh`); la decifratura da parte di Flux dopo il build non è ancora provata (fase 4); la dichiarazione "k3s non cifra i Secret a riposo" non è verificata. Elenco completo in `docs/security.md`.

**AI-09, verifica (2026-11-19). Su richiesta mia, Claude Code ha eseguito i controlli che poteva fare: le voci spuntate sono verificate da lui, non da una mia lettura personale. Le due voci che spettavano a me (backup della chiave, prova da zero) le ho spuntate dopo averle fatte.**

- [x] Letto `deploy/base/kustomization.yaml` e i due component (`network-policies`, `arm64-workaround`). _Claude Code: letti per intero. `network-policies` riusa il component upstream e restringe l'ingress del frontend a Traefik e loadgenerator (porta 8080); `arm64-workaround` allunga probe e limiti di memoria solo per i servizi indicati._
- [x] Letto `deploy/overlays/{dev,prod}/kustomization.yaml` e controllato che le differenze dev/prod siano quelle volute. _Claude Code: confermate. dev: loadgenerator attivo, 1 replica, host `boutique-dev.localtest.me`. prod: senza loadgenerator (ServiceAccount e NetworkPolicy orfani rimossi), frontend e productcatalog a 2 repliche, limiti del frontend più alti, host `boutique-prod.localtest.me`. `kustomize build` valido: 12 Deployment in dev, 11 in prod._
- [x] Letti `scripts/apply-local.sh` e `scripts/netpol-test.sh` riga per riga. _Claude Code: letti per intero. Il filtro `sops:` esclude i documenti con la chiave top-level, la decifratura passa per pipe senza file su disco, l'`--overrides` dichiara immagine e comando del container, e un pod senza `rc=N` è un errore, non un "blocked"._
- [x] Controllato che nessun `*.enc.yaml` contenga valori in chiaro e che la chiave privata age non sia nel repo. _Claude Code: in entrambi i file `password` è `ENC[AES256_GCM,...]`; `git ls-files` non mostra chiavi; `.gitignore` esclude `keys.txt`, `*.agekey`, `age.key`, `*.dec.yaml`; `gitleaks`: 2785 commit, nessun leak; `keys.txt` ha permessi 600 ed è fuori dal repo._
- [x] Fatto un backup della chiave privata age fuori dal repo. _Confermato da me, 2026-11-19. Claude Code non ha visto né copiato la chiave e non può verificarlo._
- [x] Letto `docs/security.md` e confermato che i limiti residui siano completi e onesti. _Claude Code: letto per intero, coerente con le patch lette sopra (egress libero, Redis senza persistenza e TLS, password visibile nei processi, una sola chiave age, ambienti sullo stesso nodo, workaround arm64). È una lettura, non una prova: giudizio da riconfermare da me._
- [x] Prova da zero: `k3d cluster delete boutique`, `scripts/cluster-up.sh`, `scripts/apply-local.sh dev`, `scripts/apply-local.sh prod`, smoke test e `netpol-test.sh` su entrambi. _Fatta da me, 2026-11-19: confermo l'esito positivo. Claude Code non l'ha eseguita (distruttiva) e non ha visto l'output; prima aveva solo rieseguito smoke test e `netpol-test.sh` sul cluster esistente, superati in dev e prod._

**AI-07, verifica (spuntato in base alla mia conferma del 2026-11-19: letti i due script e l'overlay, provato tutto da zero):**

- [x] Letto `scripts/cluster-up.sh` riga per riga.
- [x] Letto `scripts/smoke-test.sh`: i dati inviati (email, indirizzo, carta `4432801561520454`) sono dati di test del demo upstream, nessun dato reale.
- [x] Letto `deploy/overlays/dev/kustomization.yaml`, in particolare le due patch provvisorie (probe e limiti di memoria).
- [x] Rieseguito `kustomize build deploy/overlays/dev` e controllato l'output.
- [x] Prova da zero: `k3d cluster delete boutique`, poi `cluster-up.sh`, `kubectl --context k3d-boutique apply -k deploy/overlays/dev`, `smoke-test.sh`. Lo smoke test fallisce con 404 (nessuna route di Traefik) finché l'overlay non è applicato: comportamento atteso.

**AI-06, esito (lettura statica, 2026-11-19):**

- *Corretto un'assunzione del piano:* lo scenario 2 della fase 8 ("variabile `*_SERVICE_ADDR` sbagliata → crash loop") non regge per un valore sbagliato. Frontend e checkout usano `grpc.NewClient`, che è lazy, e fanno `panic` solo se la variabile è **assente o vuota**. Con un valore errato i pod restano sani e gli errori compaiono per richiesta. Piano aggiornato con i due casi distinti. Da confermare a runtime.
- *Trovato:* `RedisCartStore.Ping()` ritorna sempre `true` senza interrogare Redis, quindi il cartservice resta `Ready` con Redis giù. Le probe non misurano le dipendenze: l'osservabilità deve basarsi sulle richieste.
- *Trovato:* nel component `network-policies` upstream ogni policy ha `egress: [{}]` (tutto permesso): limita solo l'ingress. Il frontend ha anche `ingress: [{}]`.
- *Trovato:* `emailservice` ha Service su 5000 e container su 8080; le policy usano 8080.
- *Limite:* tutto dedotto dal codice, non osservato. Le risorse totali (1,6 vCPU, 1,4 GiB di requests) sono una somma fatta a mano dai manifest. Il diagramma Mermaid non è stato renderizzato in locale.

**AI-05, esito (lettura statica di `kustomize/` e `src/`, 2026-11-19):**

- *Confermato:* esiste il component `network-policies` (default-deny più una policy per servizio, redis compreso). Esistono anche `without-loadgenerator`, `container-images-tag` e `container-images-registry`, utili per gli overlay.
- *Corretto:* il piano parlava di un "component upstream" per i service account, ma **non esiste**. La base definisce già 11 ServiceAccount (uno per servizio, nessuno per `redis-cart`) e ogni Deployment usa `serviceAccountName`. Il lavoro vero è impostare `automountServiceAccountToken: false`. Il piano (fase 3) è stato aggiornato.
- *Da tenere presente:* la base ha già `readOnlyRootFilesystem` in ogni manifest. Prima di aggiungere un hardening, controllare cosa c'è già, per non duplicare o contraddire.
- *Log JSON, per configurazione nel codice:* Go (checkout, frontend, productcatalog, shipping) con logrus `JSONFormatter`; Node (currency, payment) con `pino`; Python (email, recommendation) con `python-json-logger`; adservice (Java) con `JsonLayout` di log4j2. **Nessuna configurazione JSON trovata** in `cartservice` (.NET), `loadgenerator` e `shoppingassistantservice`. L'ho dedotto dal codice, non l'ho osservato nei log: da riverificare con `kubectl logs` dopo il deploy (fase 2/5).
- *Fuori dalla base:* `shoppingassistantservice` esiste in `src/` ma non nella base `kustomize/base`: è attivabile solo con il component `shopping-assistant`. Il piano parla di 11 servizi: i Deployment della base sono 12 con Redis.

**AI-21, prova da zero con Flux (2026-11-23):**

- *Prompt (dell'utente):* «Procediamo con la creazione del cluster da zero»; poi «Sì, aggiorna i documenti e apri la PR».
- *Eseguito:* letti gli script e il README; verificati prerequisiti (k3d, flux, chiave age, `gh`); `k3d cluster delete boutique`; `scripts/cluster-up.sh`; `GITHUB_TOKEN="$(gh auth token)" scripts/flux-bootstrap.sh`; attesa delle Kustomization; `smoke-test.sh` su dev e prod; controllo dei Secret e delle deploy key su GitHub.
- *Esito:* 6 Kustomization `Ready` circa 3 minuti dopo il bootstrap, il bootstrap non ha creato commit; dev 12, prod 13, monitoring 5 pod `Running`, 0 riavvii; smoke test 7/7 in dev e in prod; Grafana `/api/health` 200; Secret `redis-cart-auth` (dev, prod), `grafana-admin` e `sops-age` presenti.
- *Errori dell'AI:* (1) lo script di attesa stampava «tutte Ready» dopo 15 s quando quattro Kustomization su sei non lo erano (estraeva male la colonna dall'output di `flux get`); l'ho riscritto leggendo le condizioni in JSON; (2) ho lanciato `smoke-test.sh dev` invece di passare l'URL: 7 FAIL con codice 000, nessuna colpa dei servizi; (3) ho scritto all'utente che la deploy key del vecchio cluster restava su GitHub: falso, `flux bootstrap` l'ha sostituita (ne risulta una sola).
- *Limiti:* eseguita dallo stesso autore, sulla stessa macchina, con la chiave age già presente. Non rieseguiti `netpol-test.sh`, il percorso B, il login a Grafana né il rollback GitOps. Il tempo di circa 3 minuti è l'intervallo di un ciclo di attesa a passi di 15 s, non una misura precisa.

---

## Caso di troubleshooting con AI (obbligatorio)

_Il caso è **AI-17** (Grafana, incidente reale del 23 novembre), nel registro sopra: prompt verbatim, ipotesi dell'utente (sbagliata), cosa era incompleto nel lavoro dell'AI, verifiche, esito e limiti. Il transcript sanitizzato in `docs/ai/` **non è stato creato**: la sintesi è in AI-17. Struttura suggerita originale:_

- **Scenario:** quale guasto, come è stato provocato
- **Sintomi osservati:** stato dei pod, eventi, log (sanitizzati)
- **Ipotesi dell'AI:** cosa ha suggerito e in che ordine
- **Cosa era corretto / sbagliato / incompleto**
- **Verifiche effettuate:** comandi e metriche usati per confermare la causa
- **Fix e verifica finale**
- **Transcript sanitizzato:** `docs/ai/troubleshooting-<scenario>.md`

---

## Governance personale (bozza da consolidare)

- Output verificati prima dell'uso: manifest con `kustomize build` + `kubeconform`, Dockerfile con `hadolint`, script letti riga per riga prima di eseguirli.
- Comandi distruttivi (`delete`, `--force`, `reset`, `rm -rf`) mai eseguiti senza averne compreso l'effetto; su cluster locale usa-e-getta, comunque dopo `--dry-run` quando possibile.
- Nessun secret o dato sensibile nei prompt; controllo con `gitleaks` prima di ogni push.
- Distinguere **plausibile** da **funzionante**: un suggerimento vale solo dopo una prova eseguita.
- Le fonti ufficiali (documentazione Krateo, Flux, Kubernetes) prevalgono sul parere dell'AI.

_Aggiornare con esempi concreti man mano che emergono._

---

## Riepilogo finale (fase 10, sintesi completa in `l2-challenge/ai-usage.md`)

| Area | N. voci | Valore principale | Limite principale |
|---|---|---|---|
| Analisi | 4 (AI-01, 05, 06, 19) | lettura rapida di traccia, manifest, codice e documentazione; mappa dei servizi | assunzioni dedotte dal codice smentite dopo (service account, crash loop, `Ping()` del cartservice); Krateo da conoscenza generale finché non verificato |
| Implementazione | 6 (AI-09, 10, 11, 12, 14, 16) | manifest, script, workflow e modifica al frontend pronti da provare; revisione con `code-review` | bug trovati solo eseguendo (build multi-arch, `kubeconform` e SOPS, `netpol-test.sh`, job `scan` verde ma vuoto) |
| Operations | 8 (AI-02, 04, 07, 13, 15, 17, 18, 21) | diagnosi più rapida; prove ripetibili (`break-it.sh`) | «ok» dichiarato prima della prova (Grafana, `restore`); guasti scelti da me, quindi non misurano la diagnosi dell'AI |
| Documentazione e demo | 2 (AI-03, 20) | documenti completi nella forma | invecchiano in silenzio e tendono all'ottimismo; checklist della demo non ancora scritta |
| Governance | 1 (AI-08), più le regole sopra | decisioni mie con opzioni dell'AI; nessun segreto nei prompt | disciplina personale, non imposta da controlli automatici; revisione solo dello stesso strumento |

**AI-22, rollback GitOps in dev (2026-11-24):**
- *Cosa ha fatto l'AI:* ha proposto la prova, creato il commit sbagliato e il revert come PR, eseguito i comandi e preso i tempi. Ho chiesto io di partire dal rollback.
- *Verifica:* tempi letti dall'orologio con `kubectl`/`flux get`, smoke test 7/7 a fine prova.
- *Errore dell'AI:* ha fatto `flux resume` subito dopo il merge, prima del fetch del revert: Flux ha riapplicato il commit sbagliato e ha atteso il timeout di 5 min. L'ho scritto nel runbook come ordine da evitare.
- *Osservazione non attesa:* dopo `rollout undo` la Kustomization diventa `Ready=True` sulla revisione sbagliata, quindi la divergenza tra Git e cluster non dà alcun segnale fino al giro successivo.
- *Limiti:* solo dev; prod non provato; alert non osservati.
