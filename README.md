# Online Boutique: piattaforma GitOps locale

Fork di [Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo) di Google (11 microservizi gRPC e un Redis, licenza Apache 2.0), con una piattaforma costruita intorno: k3d, Flux, Kustomize, SOPS, GitHub Actions, GHCR, Prometheus e Grafana, guasti riproducibili e runbook.

**La documentazione è in [`l2-challenge/`](l2-challenge/README.md)**: perché questa applicazione, prerequisiti, installazione, demo, stato della verifica e mappa di tutti i documenti.

- [l2-challenge/README.md](l2-challenge/README.md): punto di partenza
- [l2-challenge/ai-usage.md](l2-challenge/ai-usage.md): uso dell'AI, con limiti
- [docs/](docs/): architettura, GitOps, sicurezza, CI, osservabilità, runbook, Krateo, ADR
- [AI-LOG.md](AI-LOG.md) e [PIANO_DI_LAVORO.md](PIANO_DI_LAVORO.md): diario di lavoro e piano

I comandi si eseguono dalla radice di questo repository.

## Dell'applicazione originale

Online Boutique è un negozio online di esempio creato da Google per dimostrare Kubernetes, gRPC e i prodotti Google Cloud. Il README originale, con il Quickstart per GKE, le opzioni di deploy (Terraform, Istio, Helm) e l'elenco dei video e articoli che la usano, è nel repository upstream: <https://github.com/GoogleCloudPlatform/microservices-demo>. Le cartelle upstream che questa piattaforma non usa (`terraform/`, `helm-chart/`, `istio-manifests/`, `kubernetes-manifests/`, `release/`) restano al loro posto; l'elenco è nel [README](l2-challenge/README.md#perché-online-boutique).

![Architettura](docs/img/architecture-diagram.png)

Il codice dell'applicazione è © Google, licenza Apache 2.0 ([LICENSE](LICENSE)).
