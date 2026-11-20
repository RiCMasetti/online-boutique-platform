# ADR 0002 — Immagini multi-architettura per tutti i servizi

- **Data:** 2026-11-19
- **Stato:** accettata
- **Collegata a:** ADR 0001 (scelta di k3d e di GHCR), `docs/architecture.md` §10

## Contesto

Il primo deploy della base upstream su k3d (nodo arm64, Apple Silicon) ha mostrato che le immagini `us-central1-docker.pkg.dev/online-boutique-ci/microservices-demo/*:v0.10.7` sono **solo amd64** (verificato con `crictl inspecti`). Girano emulate, con Rancher Desktop in modalità QEMU senza Rosetta. Effetti osservati: probe gRPC in timeout (exit 137), poi `OOMKilled` su cartservice, currencyservice e paymentservice. Il registry di rilascio `us-docker.pkg.dev/google-samples/...` risponde 403 in accesso anonimo, quindi non offre una variante multi-arch utilizzabile.

Il progetto deve mantenere la compatibilità in ambiente di sviluppo su macchine con architetture diverse, arm64 o amd64, senza interventi manuali.

## Decisione

Costruire **tutti gli 11 servizi della base** (adservice, cartservice, checkoutservice, currencyservice, emailservice, frontend, loadgenerator, paymentservice, productcatalogservice, recommendationservice, shippingservice) come immagini multi-architettura `linux/amd64` e `linux/arm64`, pubblicate su GHCR con tag = SHA del commit. Gli overlay Kustomize puntano a queste immagini.

Restano esclusi `redis:alpine` e l'immagine `busybox` dell'init container, già multi-arch, e `shoppingassistantservice`, che non è usato (vedi `docs/architecture.md` §5).

## Motivazione

- Mantiene la compatibilità in ambiente di sviluppo su arm64 e amd64, senza emulazione e senza workaround.
- Elimina le patch provvisorie dell'overlay dev (probe rilassate, limiti di memoria alzati).
- I Dockerfile upstream usano `--platform=$BUILDPLATFORM` e `TARGETARCH`, ma **non vanno bene così com'erano** (correzione del 2026-11-20, fase 5): dichiarano i default `ARG BUILDPLATFORM=linux/amd64` (in tutti e 12 i Dockerfile) e `ARG TARGETARCH=amd64` (frontend, checkoutservice, productcatalogservice, shippingservice, cartservice), che sovrascrivono i valori di buildx. Provato sul frontend: `docker buildx build --platform linux/arm64` produceva un binario x86-64 (identico a quello amd64) e compilava in emulazione (5 minuti invece di circa 50 secondi). Nel frontend i default sono stati rimossi; vanno rimossi in tutti gli altri in fase 6, e la CI deve controllare l'architettura del binario, non solo l'etichetta dell'immagine.
- La CI della fase 6 deve comunque costruire e pubblicare almeno il frontend: estenderla a undici servizi con una matrice ha un costo marginale basso.

## Trade-off

- **Manutenzione:** undici immagini invece di una; di fatto un fork delle immagini upstream. La licenza (Apache 2.0) lo consente. Va dichiarato nella documentazione finale.
- **Tempo di build:** la prima build è lunga, soprattutto per Java e .NET. Da misurare in fase 6. Costruire arm64 con QEMU in CI è lento: da verificare nella documentazione di GitHub se i runner arm64 sono disponibili e gratuiti per un fork pubblico, prima di contarci.
- **Visibilità su GHCR:** i pacchetti devono essere pubblici perché chiunque possa scaricarli senza login. Da verificare e impostare alla prima push.
- **Demo senza rete:** il piano B della fase 11 scarica le immagini sulla macchina di demo e le importa con `k3d image import`, che usa l'architettura locale.

## Aggiornamento (fase 6, 2026-11-20)

La CI costruisce ogni servizio su **runner nativi** (`ubuntu-24.04` e `ubuntu-24.04-arm`, gratuiti per il fork pubblico) e unisce i risultati in un manifest, invece di usare QEMU o la cross-compilazione: nei Dockerfile Python lo stadio `builder` gira sulla piattaforma di build e i suoi pacchetti finiscono nell'immagine finale, quindi un cross-build avrebbe prodotto librerie della piattaforma sbagliata (dedotto dai Dockerfile, non provato). I default `amd64` sono stati rimossi da tutti gli 11 Dockerfile. Dettagli in [docs/ci.md](../ci.md).

## Transizione

Fino alla fase 6 gli overlay usano le immagini upstream con i workaround già presenti in `deploy/overlays/dev`. A fine fase 6 si cambiano registry e tag (component `container-images-registry` e `container-images-tag`) e si rimuovono i workaround. L'ADR va rivista se la build di qualche servizio non è fattibile su una delle due architetture: in quel caso si documenta l'eccezione.

## Alternative scartate

- **Solo il frontend custom, gli altri upstream amd64 emulati** (piano B delle metriche): i workaround diventano permanenti e la demo su Apple Silicon resta fragile. Rimane il piano B se il tempo stringe.
- **Passare a VZ con Rosetta in Rancher Desktop:** non provato. Potrebbe migliorare il solo ambiente locale, ma non risolve la compatibilità su altre configurazioni di sviluppo né la CI, e Rosetta con JVM e .NET non è stato verificato. Non è una soluzione per il progetto.
