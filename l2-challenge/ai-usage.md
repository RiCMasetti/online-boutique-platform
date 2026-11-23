# Uso dell'AI nel progetto

Strumento: **Claude Code** (estensione VS Code), modello Claude Sonnet 5.5, usato per tutto il lavoro. Nessun altro strumento AI.

Questo documento è la sintesi. Il materiale grezzo, con prompt, decisioni ed errori giorno per giorno, è in [AI-LOG.md](../AI-LOG.md); gli identificativi `AI-NN` rimandano a lì. Dove un esito dipende da una verifica, la verifica è nominata. Dove non c'è, è scritto.

## In breve

- **20 voci** nel diario (`AI-01`…`AI-20`), fasi 0-10. Per area: analisi 4, implementazione 6, operations 7, documentazione 2, governance 1. La suddivisione è l'etichetta data alla voce, non il tempo speso: la documentazione è stata scritta dentro quasi tutte le voci di implementazione e di operations, quindi quella riga sottostima il suo peso.
- **Esito per voce:** 5 accettate, 14 modificate, 1 mista (`AI-01`). **Nessuna voce è stata scartata per intero**; gli scarti (opzioni, ipotesi, rilievi di una revisione) stanno dentro le voci.
- **Dove l'AI ha dato più valore:** velocità di lettura (traccia, documentazione, codice di 11 servizi), scrittura di manifest, script e documenti da controllare, esecuzione dei controlli ripetitivi.
- **Dove ha sbagliato più spesso:** dichiarare «verificato» o «ok» prima di una prova vera, e dedurre dal codice un comportamento che il cluster ha poi smentito (esempi sotto). Il rimedio che ha funzionato è sempre stato lo stesso: eseguire.

## 1. Analisi

**Cosa ho chiesto:** lettura dei requisiti della challenge e piano a 10 giorni (`AI-01`); mappa dei servizi, delle dipendenze e dei punti critici (`AI-05`, `AI-06`); valutazione di Krateo dalla documentazione (`AI-19`).

**Valore:** un documento di 7 pagine ridotto a deliverable, pesi e rischi in una sessione; una mappa di 12 Deployment e dei loro `*_SERVICE_ADDR` che a mano avrebbe richiesto molta più lettura incrociata di manifest e `.proto`.

**Limiti, con prove:**
- Il piano partiva da un'ipotesi sbagliata sui service account: il «component upstream» non esiste (`AI-05`).
- Prevedeva che un `*_SERVICE_ADDR` sbagliato causasse un crash loop. Dal codice (client gRPC *lazy*) non è così: solo un valore **assente** manda in crash. Confermato dal vivo in fase 8 (`AI-06`, `AI-18`).
- Su Krateo l'AI ha dichiarato di descriverlo dalla conoscenza generale. L'ho verificato sulle pagine del sito: prima con un riassunto di `WebFetch` (che riassume con un modello più piccolo, non è una lettura), poi scaricando e leggendo per intero 19 pagine. La raccomandazione «non adottare ora» poggia su requisiti dichiarati dalla documentazione che **non ho misurato né provato**; nessun PoC (`AI-19`).

**Cosa ho fatto io:** ho riletto il PDF originale e confrontato la sintesi; ho confermato nella documentazione ufficiale che le composition Krateo usano chart Helm.

## 2. Implementazione

**Cosa ho chiesto:** overlay e hardening (`AI-09`), Flux con SOPS (`AI-10`), metriche del frontend e Dockerfile (`AI-11`), sidecar `redis_exporter` (`AI-12`), CI multi-arch (`AI-14`), stack Prometheus (`AI-16`).

**Valore:** manifest, script e workflow pronti da eseguire e correggere; una modifica al frontend (contatore e istogramma, 3 test) e il resto della catena fino al push su GHCR.

**Errori trovati provando, non rileggendo:**
- **Bug upstream di build multi-arch:** i default `ARG BUILDPLATFORM=linux/amd64` annullavano buildx; l'immagine «arm64» conteneva un binario x86-64. Notato solo perché le dimensioni delle due immagini differivano di 9 byte; l'etichetta diceva `linux/arm64` (`AI-11`). L'ADR 0002 dava per buoni i Dockerfile upstream: corretto.
- **`kubeconform` bocciava il Secret SOPS**, `go test` falliva su `checkoutservice` per `go vet`, il job `scan` era verde ma non scansionava nulla (riferimento con maiuscole), l'`images:` degli overlay era un no-op (`AI-14`).
- **`netpol-test.sh` passava per il motivo sbagliato:** contava come «bloccato» anche un pod non creato (`AI-09`).
- **Sbaglio di ragionamento dell'AI:** aveva previsto che lo stack avrebbe avuto problemi di memoria; il problema vero è stata la CPU di Grafana (`AI-16`, `AI-17`).

**Revisione indipendente:** la PR dello stack di osservabilità è stata rivista con la skill `code-review` di Claude Code (livello medio). Sei rilievi: quattro accettati (uno con prova: `RedisDown` produceva due alert per un solo guasto, verificato con `promtool test rules`), uno scartato dopo averlo controllato, uno riconosciuto e non corretto (`AI-16`). Non è una revisione umana: è lo stesso strumento in un'altra modalità.

## 3. Operations

**Cosa ho chiesto:** verifica dei tool e delle risorse (`AI-02`), pulizia del repository e `gitleaks` (`AI-04`), diagnosi dei pod in crash al primo deploy (`AI-07`), verifica dei log e delle probe con guasto provato (`AI-13`), promozione di prod (`AI-15`), l'incidente di Grafana (`AI-17`), i cinque guasti riproducibili e il runbook (`AI-18`).

**Il caso di troubleshooting (`AI-17`).** Prompt dell'utente: «Grafana è down, credo per un problema di memoria, non ho indagato.»
- *Ipotesi dell'utente:* memoria. **Sbagliata:** memoria 281 MiB su 384 di limite, `Exit Code 137` ma `Reason: Error` e non `OOMKilled`, CPU a 4,4 core, nodo all'86%. La liveness uccideva Grafana saturo di CPU. L'AI ha guardato `Reason` e la CPU prima di rispondere; senza quel controllo la via ovvia sarebbe stata alzare il limite di memoria (inferenza, non provata).
- *Dove ha sbagliato l'AI:* aveva documentato Grafana come «calma» dopo pochi minuti; dopo la correzione (PR #10) ha guardato 5 minuti e detto «ok». Dopo circa 25 minuti era di nuovo al limite. Me ne sono accorto io. Aveva chiamato «verificato» un controllo che non riproduceva l'uso che aveva causato il problema.
- *Esito:* causa più probabile il carico di query dal browser (Metrics Drilldown); **non provata**, nessuna correzione ulteriore applicata.
- Raccolta di eventi e log: pod, `describe`, `top`, eventi e log di Grafana. Il transcript sanitizzato dei comandi non è stato conservato come file separato: la sintesi è in `AI-17`.

**Guasti riproducibili (`AI-18`).** Provati tutti e cinque. Errori miei trovati solo eseguendo: `status` segnava «non sano» ogni pod (backreference in `awk`); il primo `low-memory` veniva rifiutato dall'API e lasciava Flux sospesa; **`restore` dichiarava «completato» con il frontend ancora a 0 repliche**: l'ho visto dallo smoke test, non dallo script. Limite dichiarato: i guasti li avevo scelti io e conoscevo la risposta, quindi i tempi non misurano la qualità della diagnosi dell'AI.

**Valore:** diagnosi più rapida (`describe`, `logs --previous`, eventi, metriche lette insieme) e prove ripetibili. **Limite:** l'AI non ha mai avuto il contesto di ciò che avevo aperto nel browser; il dato decisivo nel caso Grafana l'ho dato io.

## 4. Documentazione e demo

**Cosa ho chiesto:** ADR, `architecture.md`, `security.md`, `gitops.md`, `ci.md`, `observability.md`, `runbook.md`, `krateo-evaluation.md`, questo README.

**Valore:** documenti completi e coerenti nella forma. **Limite principale: la documentazione scritta dall'AI invecchia in silenzio e tende all'ottimismo.** Esempi trovati:
- `docs/architecture.md` apre ancora con «nulla è stato ancora osservato a runtime», benché la sezione 10 riporti le osservazioni del primo deploy; `docs/gitops.md` diceva che una PR non era stata unita quando lo era (`AI-15`); una riga sulla password di Redis era obsoleta (`AI-13`).
- Il controllo di coerenza della fase 10 ([consistency-check.md](consistency-check.md)) ne ha trovati altri.
- Dove un comando non è stato eseguito, i documenti lo dicono («non provato»). È una regola, non un'abitudine dell'AI: l'ho dovuta chiedere e ricontrollare.

**Demo:** la checklist con i comandi e i tempi (fase 11) **non esiste ancora**.

## 5. Governance

Regole che ho applicato (bozza in [AI-LOG.md](../AI-LOG.md), con gli esempi):

| Regola | Come è stata applicata |
|---|---|
| Nessun segreto nei prompt né nel repository | la chiave age privata non è mai stata stampata né incollata in un prompt; token solo da variabile d'ambiente; `gitleaks` su 2785 commit senza rilievi; `.gitignore` esclude chiavi e file in chiaro |
| Nessun comando eseguito senza averlo capito | script letti riga per riga prima di eseguirli; per le voci critiche la lista «Verifica» spuntata da me |
| Distruttivo solo con permesso | le azioni distruttive sono passate dal sistema di permessi: due volte sono state bloccate (`git reset --hard`, installazione di `actionlint`) e non le ho aggirate |
| «Plausibile» non è «funzionante» | un suggerimento vale dopo una prova eseguita; le voci riportano cosa **non** è stato verificato |
| Le fonti ufficiali prevalgono | documentazione Krateo letta dal sito, versione del chart scaricata con `helm pull` prima di fidarsi |
| Le decisioni sono mie | opzioni proposte dall'AI, scelta mia: immagini multi-arch (`AI-08`), promozione di prod; i merge delle PR li faccio io |

**Limite:** nulla di questo è imposto da un controllo automatico, salvo `gitleaks` in pre-commit e i controlli in CI. Il resto è disciplina personale, quindi dipende da me.

## Cosa cambierei

- Prima verificare, poi scrivere «ok»: i tre errori più costosi (Grafana due volte, `restore`) erano dichiarazioni di successo anticipate.
- Scrivere i documenti **dopo** l'esecuzione e con la data accanto a ogni «provato».
- Chiedere una revisione umana: la revisione fatta è dello stesso strumento.
