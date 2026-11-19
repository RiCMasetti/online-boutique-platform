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
    - [ ] Rileggere il PDF originale e confrontarlo con la sintesi (deliverable e passi della demo).
    - [ ] Verificare nella documentazione ufficiale di Krateo che le composition si basino su chart Helm.
    - [ ] Verificare che k3s applichi le NetworkPolicy di default.
    - [ ] Verificare quali servizi di Online Boutique emettono log JSON e che la base `kustomize/` upstream contenga i component indicati.
    - [ ] Confermare scadenza e risorse della mia macchina (RAM di Docker) prima di accettare il calendario.
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
| AI-03 | 1 | documentazione | Claude Code | Prima bozza di `docs/adr/0001-scelte-di-progetto.md` dalla tabella del piano | _da decidere dopo la rilettura_ | Da rileggere e correggere da me: le voci su NetworkPolicy di k3s, component upstream e log JSON restano non verificate e sono dichiarate tali nell'ADR |

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
