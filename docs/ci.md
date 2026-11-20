# CI e rilascio delle immagini (fase 6)

## 1. Panoramica

```
PR verso main ──► ci.yaml ──► checks.yaml (hadolint, kustomize+kubeconform, test)
                         └──► build-images.yaml (push=false, solo servizi con modifiche in src/<svc>/)

push su main ───► release.yaml ──► checks.yaml
  (src/** o workflow)         ├──► build-images.yaml (push=true, tutti gli 11 servizi)
                              ├──► scan (Trivy, non bloccante)
                              └──► update-dev: commit del tag in deploy/components/dev-images
                                                    │
                                          Flux (boutique-dev) applica il commit ──► rollout in dev
```

I workflow upstream `ci-pr.yaml` e `ci-main.yaml` sono stati sostituiti: provavano solo due servizi Go e il cartservice e non pubblicavano nulla. `kustomize-build-ci.yaml` (controlla la cartella upstream `kustomize/`) resta com'è.

| File | Ruolo |
|---|---|
| `.github/workflows/checks.yaml` | Riusabile. `hadolint`, `kustomize build` + `kubeconform` su dev e prod, `go test` (frontend, productcatalog, shipping, checkout), `dotnet test` (cartservice) |
| `.github/workflows/build-images.yaml` | Riusabile. Matrice servizio × architettura su runner nativi, poi manifest multi-arch |
| `.github/workflows/ci.yaml` | Sulle PR verso `main` |
| `.github/workflows/release.yaml` | Su push a `main` (o a mano con `workflow_dispatch`) |

## 2. Scelte

- **Runner nativi, non QEMU né cross-build.** `ubuntu-24.04` per `amd64`, `ubuntu-24.04-arm` per `arm64` (gratuito sui repository pubblici; il fork lo è). Motivo: nei Dockerfile Python lo stadio `builder` gira sulla piattaforma di build e i suoi pacchetti (con estensioni compilate, come gRPC) vengono copiati nello stadio finale; in cross-build l'immagine `arm64` conterrebbe librerie `amd64` e fallirebbe all'avvio. Con runner nativi build e destinazione coincidono. In più i build non passano per l'emulazione.
- **Un'immagine per servizio e per architettura, poi un manifest.** Ogni job pubblica per digest (senza tag); il job `merge` crea `ghcr.io/ricmasetti/online-boutique-platform/<servizio>:<tag>` e fallisce se le piattaforme non sono esattamente `linux/amd64` e `linux/arm64`.
- **Tag = primi 12 caratteri dello SHA del commit.** Nessun tag mobile (`latest`, `main`): ogni deploy è riproducibile e il rollback è un `git revert` del commit del tag.
- **Controllo dell'architettura prima del push:** ogni build viene prima caricata nel daemon del runner e si verifica `Architecture`. È un controllo sull'etichetta; la garanzia vera è che il runner è nativo. Il controllo sul binario (`file`) l'ho fatto a mano in locale (shippingservice e cartservice, `aarch64`), non è automatizzato.
- **Dockerfile:** tolti in tutti gli 11 servizi i default `ARG BUILDPLATFORM=linux/amd64`, `TARGETOS=linux`, `TARGETARCH=amd64` (stesso difetto già corretto nel frontend in fase 5, [ADR 0002](adr/0002-immagini-multi-arch.md)). Il `shoppingassistantservice` non è toccato: non è nella base.
- **hadolint:** soglia `error` su tutti i Dockerfile, soglia `warning` sul frontend (riscritto da noi, pulito). I warning dei Dockerfile upstream (`DL3018` e simili) non sono corretti.
- **kubeconform con `-skip Secret`:** il Secret cifrato con SOPS ha la chiave `sops` alla radice, non ammessa dallo schema Kubernetes (Flux la toglie decifrando). Trovato eseguendo il controllo in locale. È l'unico Secret negli overlay.
- **Il tag di dev sta in un component** (`deploy/components/dev-images`), non nell'overlay: `kustomize edit` riscrive il file e cancella i commenti, e nell'overlay ce ne sono di importanti. Il workflow aggiorna le 11 immagini con `kustomize edit set image`.
- **Commit automatico su `main`** (invece di una PR): il commit fatto con `GITHUB_TOKEN` non innesca altri workflow, quindi non c'è un ciclo; Flux lo legge al giro successivo. Con un solo repository e nessuna branch protection è la strada più semplice. Se `main` avanza durante il job, il push riprova dopo un `rebase` (fino a 3 volte). Conseguenza pratica: dopo ogni release serve `git pull` in locale.
- **Prod non viene toccato dalla CI** (ADR 0003): la promozione è una PR `main → prod` che porta con sé il tag scelto nell'overlay prod.

## 3. Cose da fare a mano (non automatizzabili da qui)

1. **Rendere pubblici i pacchetti GHCR dopo la prima pubblicazione.** I pacchetti creati da un workflow nascono privati: su GitHub, *Packages → <servizio> → Package settings → Change visibility → Public*, per ciascuno degli 11. Il job `update-dev` lo controlla (pull anonimo) e **non aggiorna il tag** se un'immagine non è leggibile, per non mandare dev in `ImagePullBackOff`. Alternativa non scelta: un `imagePullSecret` con un token.
2. **Workflow permissions del repository:** il default è `read`; i job dichiarano i permessi di cui hanno bisogno (`packages: write`, `contents: write` solo in `update-dev`). Nessuna impostazione da cambiare.

## 4. Stato della verifica

| Cosa | Stato |
|---|---|
| `hadolint` (soglie sopra) sugli 11 Dockerfile | eseguito in locale, ok |
| `kustomize build` + `kubeconform` su dev e prod | eseguito in locale, ok (dopo `-skip Secret`) |
| `go test ./...` di frontend, productcatalog, shipping, checkout | eseguito in locale, ok (dopo il fix sotto) |
| Build `arm64` di shippingservice e cartservice con i Dockerfile corretti | eseguita in locale, binari `aarch64` |
| Simulazione del passo `kustomize edit set image` | eseguita su una copia: 11 immagini GHCR nel rendering di dev, resto invariato |
| Sintassi YAML dei workflow | letta con un parser YAML; **`actionlint` non eseguito** |
| Run della PR #2 su GitHub (2026-11-20): `checks` (hadolint, manifests, test) e le 22 build (11 servizi × amd64/arm64, senza push) | **tutti passati**; build da 46 s (recommendationservice arm64) a 161 s (cartservice arm64), cache fredda |
| Build `amd64` | passata sui runner |
| Push su GHCR, job `merge`, `update-dev`, rollout in dev (run 44726672556, tag `06974f96d9ae`) | passati; adservice amd64 ha richiesto un secondo tentativo per un `429` di Maven Central |
| Job `scan` (Trivy) | al primo run falliva ovunque (riferimento con maiuscole, PR #3); dal run 44731010825 funziona e riporta vulnerabilità |
| Dev senza `arm64-workaround` (run 44731010825, tag `e7eaa5b8b502`) | 12 deployment pronti, 0 restart, smoke test superato, memoria tra 11 e 74 MiB (limiti 128-450 MiB) |

**Correzione trovata dai controlli:** `go test` su `checkoutservice` falliva (`go vet`: `status.Errorf(codes.Internal, err.Error())` usa un messaggio come stringa di formato). Corretto in `src/checkoutservice/main.go` con `status.Error`: stesso comportamento, ma un `%` nel messaggio non viene più interpretato. Upstream non lo vedeva perché non testava quel servizio.

### Trivy: prima scansione (2026-11-20, tag `e7eaa5b8b502`, solo HIGH e CRITICAL con fix disponibile)

Il job stampa più tabelle per immagine (sistema operativo e librerie); i totali sotto sono quelli stampati, senza distinguere quale sia quale.

| Servizio | Totali stampati |
|---|---|
| adservice | 17 (16 HIGH, 1 CRITICAL); 8 (6 HIGH, 2 CRITICAL) |
| cartservice | 4 (HIGH) |
| checkoutservice, frontend, productcatalogservice, shippingservice | 6 (HIGH) ciascuno |
| currencyservice, paymentservice | 5 (HIGH); 23 (22 HIGH, 1 CRITICAL) |
| emailservice, recommendationservice | 12 (HIGH); 19 (17 HIGH, 2 CRITICAL) |
| loadgenerator | 12 (HIGH); 17 (14 HIGH, 3 CRITICAL) |

Non sono state analizzate né corrette: sono dipendenze e immagini di base upstream. Lo scan non è bloccante per scelta (il piano lo vuole come plus). Un'eventuale correzione (aggiornare immagini di base e dipendenze) è fuori dal perimetro di questa fase.

## 5. Dopo il primo rilascio

- [x] Primo rilascio (run 44726672556, tag `06974f96d9ae`): pacchetti pubblici, `update-dev` ha committato il tag, rollout in dev su arm64 senza emulazione (12 deployment, 0 restart, smoke test superato).
- [x] Workaround arm64 tolto da **dev**. In prod non si poteva togliere senza passare alle immagini GHCR (con le upstream amd64 si sarebbe rotto): è stato fatto con la promozione (sotto).
- [x] Probe e memoria di dev senza workaround, con il loadgenerator attivo: 0 restart, nessun OOM, memoria molto sotto i limiti. Restano eventi `Unhealthy` (15) di **readiness** con timeout di 1 s, concentrati negli avvii dei pod durante i rollout (nodo occupato); nessuna ha portato a un riavvio. Non misurato: comportamento con più traffico del loadgenerator o a regime dopo ore.
- [ ] **Promozione di prod** (ADR 0003), in due passi in quest'ordine:
  1. PR verso `main`: nell'overlay prod il blocco `images` (10 servizi, GHCR, tag `e7eaa5b8b502`, lo stesso verificato in dev) e via il component `arm64-workaround`, che si elimina perché non lo usa più nessuno. La CI non tocca questo blocco.
  2. PR `main → prod` (`gh pr create --base prod --head main`). Porta in prod **tutto** ciò che `main` ha in più, non solo le immagini: `ENV_PLATFORM` sul frontend (log JSON puliti), il sidecar `redis_exporter` e la porta `metrics` sul Service di Redis (fase 5), le immagini con `/metrics`.
  Dopo il merge: pod di prod `Ready` con l'immagine nuova, smoke test su `http://boutique-prod.localtest.me:8080`, restart a zero, `kubectl top`. Il nodo ha spazio (requests al 60% di CPU e al 30% di memoria con dev e prod accesi).
- [x] Durata dei build: 46-161 s con cache fredda (§4). Per i runner arm64: disponibili e gratuiti sul fork pubblico (ADR 0002).
