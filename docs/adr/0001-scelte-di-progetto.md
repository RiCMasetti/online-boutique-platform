# ADR 0001 — Scelte di progetto iniziali

- **Data:** 2026-11-19
- **Stato:** accettata
- **Contesto del progetto:** challenge L2, piattaforma di deploy e operations per un'applicazione a microservizi su Kubernetes locale, con GitOps, osservabilità, CI, gestione dei failure e valutazione di Krateo.

## Contesto

Servono un workload realistico (più servizi, comunicazione di rete, uno stato), un cluster ricreabile in pochi minuti su un laptop, un flusso GitOps completo e abbastanza osservabilità da diagnosticare guasti riprodotti di proposito. Il tempo è limitato (10 giorni) e la demo deve funzionare anche da cluster distrutto.

Vincoli noti:

- Macchina di sviluppo: macOS (Apple Silicon), Docker tramite Rancher Desktop, RAM della VM alzata rispetto ai 7,6 GiB iniziali.
- Il repository è un fork pubblico di `GoogleCloudPlatform/microservices-demo` (verificato con `gh repo view`: `isFork: true`, visibilità `PUBLIC`). GitHub non permette di rendere privato un fork di un repo pubblico, quindi tutto ciò che si committa è pubblico fin dal primo giorno.

## Decisioni

### 1. Workload: Google Online Boutique

- **Scelta:** usare Online Boutique (`microservices-demo`) come applicazione.
- **Motivazione:** 11 servizi che comunicano via gRPC, un frontend HTTP, Redis per il carrello e un loadgenerator già incluso. Ha una base Kustomize upstream, quindi non si parte da zero. Offre abbastanza punti di rottura per i failure scenario (dipendenze tra servizi, variabili `*_SERVICE_ADDR`, limiti di risorse).
- **Trade-off:** l'app non espone metriche Prometheus e non ha secret reali né un vero worker asincrono. Serve una modifica mirata al frontend per le metriche (fase 5) e un caso di secret costruito per la challenge (fase 3). Il mapping dei componenti richiesti dalla traccia sull'app reale va dichiarato apertamente nella documentazione.

### 2. Cluster: k3d

- **Scelta:** k3d (k3s dentro container Docker).
- **Motivazione:** si crea e si distrugge in pochi secondi, include Traefik come ingress, il port-mapping dal loadbalancer è semplice (`8080:80@loadbalancer`) e si adatta a una demo ripetuta da zero.
- **Trade-off:** è un cluster singolo, non rappresenta la topologia di produzione. Da verificare nella fase 3 che il controller di k3s applichi davvero le NetworkPolicy.
- **Alternative scartate:** kind, minikube.

### 3. Packaging dell'app: Kustomize

- **Scelta:** base upstream più overlay `dev` e `prod`.
- **Motivazione:** riuso diretto della cartella `kustomize/` upstream, patch leggibili e integrazione nativa con la `Kustomization` di Flux.
- **Trade-off:** meno parametrizzazione di un chart Helm. Le differenze tra ambienti si esprimono solo con patch e componenti. Helm resta usato dove serve, per lo stack di piattaforma (`HelmRelease`).
- **Alternativa scartata:** Helm anche per l'app (un chart separato da mantenere in parallelo alla base upstream).

### 4. GitOps: Flux

- **Scelta:** Flux con `Kustomization` e `HelmRelease`.
- **Motivazione:** gestisce nativamente Kustomize e Helm, supporta la decrittazione SOPS e l'ordinamento con `dependsOn`.
- **Trade-off:** nessuna UI integrata come in Argo CD. Lo stato si legge con `flux get` e con le metriche.
- **Alternativa scartata:** Argo CD.

### 5. Metriche: Prometheus (kube-prometheus-stack)

- **Scelta:** kube-prometheus-stack installato con `HelmRelease`.
- **Motivazione:** standard di fatto, include Grafana e le CRD `ServiceMonitor` e `PrometheusRule`.
- **Trade-off:** consuma RAM (da qui la verifica delle risorse di Docker). Alertmanager e retention si possono ridurre se serve.
- **Alternativa scartata:** approccio solo OpenTelemetry.

### 6. Secret: SOPS con age

- **Scelta:** secret cifrati nel repo con SOPS e chiavi age, decrittati da Flux.
- **Motivazione:** nessun valore in chiaro nel repository, nessun controller aggiuntivo oltre a Flux.
- **Trade-off:** la chiave privata age va custodita fuori dal repo e rigenerata a ogni cluster nuovo. Non c'è rotazione automatica. Il secret dell'app è un caso costruito per la challenge, da dichiarare come tale.
- **Alternativa scartata:** Sealed Secrets.

### 7. Registry e CI: GitHub Actions con GHCR

- **Scelta:** GitHub Actions per i controlli e la build, GHCR come registry.
- **Motivazione:** gratuito e integrato nel fork.
- **Trade-off:** i workflow upstream puntano a un progetto Google Cloud che non appartiene a questo fork e non possono funzionare qui. Vanno disattivati o sostituiti.
- **Alternativa scartata:** GitLab CI.

### 8. Ambienti: due namespace nello stesso cluster

- **Scelta:** `boutique-dev` e `boutique-prod` nello stesso cluster k3d.
- **Motivazione:** soddisfa il requisito di avere ambienti distinti con un costo di risorse accettabile in locale.
- **Trade-off:** non c'è isolamento reale tra gli ambienti (stesso control plane, stesse risorse del nodo). Va indicato tra i limiti residui.
- **Alternativa scartata:** due cluster.

## Conseguenze

- Ogni cambio dopo la fase 4 passa da Git, compresi gli aggiornamenti dell'immagine.
- Le scelte sono rivedibili. Se una verifica (per esempio sulle NetworkPolicy di k3s) le smentisce, si aggiunge una nuova ADR che sostituisce questa invece di modificarla.
- Cose ancora da verificare e non date per certe: comportamento delle NetworkPolicy su k3s, presenza dei component indicati nella base `kustomize/` upstream, servizi che emettono log JSON.
