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
    - [x] Verificare nella documentazione ufficiale di Krateo che le composition si basino su chart Helm. _Fatto da me, 2026-11-19: confermati chart Helm, OCI, tgz e private registry. Fonte: https://docs.krateo.io/how-to-guides/kco-operations/deploy-composition-definition/ (indicata da me). Doppio controllo di Claude Code il 2026-11-19 con WebFetch: la pagina conferma chart Helm, OCI, `.tgz` e private registry (blocco `credentials` con `passwordRef`), e indica come prerequisito un `values.schema.json` nella root del chart. Limite: WebFetch riassume la pagina con un modello più piccolo, quindi citazioni ed esempi non sono una lettura integrale. Resta da leggere la pagina direttamente prima della fase 9._
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
| AI-15 | 6 | operations | Claude Code | Fase 6: preparazione della promozione di prod (immagini GHCR, via `arm64-workaround`) e PR `main → prod` | mod. | PR preparate, **non unite**: nessuna verifica in prod ancora. Dettagli sotto |

**AI-15, preparazione della promozione di prod (2026-11-20, non ancora eseguita):**

- *Preparato:* overlay prod con le 10 immagini GHCR nel tag già verificato in dev (`e7eaa5b8b502`), eliminato il component `arm64-workaround`, documentazione allineata. Due PR: una verso `main`, poi `main → prod` come bozza.
- *Verificato prima:* `kustomize build` di dev e prod, `kubeconform`; diff del rendering di prod prima e dopo (solo immagini, probe e limiti del workaround); diff del rendering di **ciò che prod esegue oggi** (branch `prod`) contro quello nuovo.
- *Sorpresa:* la promozione `main → prod` porta in prod anche modifiche non legate alle immagini (sidecar `redis_exporter`, porta `metrics` sul Service, `ENV_PLATFORM`), perché prod era rimasta indietro dalla fase 4. L'avevo descritta come "solo il tag"; il diff del rendering l'ha corretta. Inoltre `docs/gitops.md` diceva che la PR #1 non era stata unita, ma `prod` era già a `88fec121`: documento obsoleto, corretto.
- *Capacità:* requests al 60% di CPU e al 30% di memoria sul nodo con dev e prod accesi; il rollout di prod non dovrebbe saturarlo. Stima da `kubectl describe node`, non provata.
- *Limiti dichiarati:* nulla è stato applicato a prod; il comportamento delle probe da 1 s in prod (2 repliche di frontend e productcatalog) è da verificare dopo il merge.

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

---

## Caso di troubleshooting con AI (obbligatorio)

_Da compilare nella fase 8. Struttura suggerita:_

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

## Riepilogo finale (da compilare alla fase 10)

| Area | N. voci | Valore principale | Limite principale |
|---|---|---|---|
| Analisi | | | |
| Implementazione | | | |
| Operations | | | |
| Documentazione e demo | | | |
| Governance | | | |
