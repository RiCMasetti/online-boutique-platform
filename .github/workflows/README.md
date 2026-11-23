# GitHub Actions

Questo fork usa i workflow della piattaforma (fase 6, descritti in [docs/ci.md](../../docs/ci.md)). I workflow upstream che si autenticavano sul progetto Google Cloud (deploy su GKE, cleanup, release) e i due che provavano solo alcuni servizi (`ci-pr.yaml`, `ci-main.yaml`) sono stati rimossi o sostituiti; restano nella cronologia e nel remote `upstream`.

| Workflow | Quando | Cosa fa |
|---|---|---|
| [checks.yaml](checks.yaml) | riusabile | `hadolint`, `kustomize build` + `kubeconform` su dev, prod e osservabilità, `promtool` sulle regole, `go test` e `dotnet test` |
| [build-images.yaml](build-images.yaml) | riusabile | build per servizio e architettura (`amd64`, `arm64`, runner nativi) e manifest multi-arch |
| [ci.yaml](ci.yaml) | PR verso `main` | controlli, più build senza push dei servizi modificati |
| [release.yaml](release.yaml) | push su `main` (`src/**` o workflow) o a mano | controlli, build e push su GHCR di tutti gli 11 servizi, scansione Trivy (non bloccante), commit del tag in `deploy/components/dev-images` |
| [kustomize-build-ci.yaml](kustomize-build-ci.yaml) | upstream, invariato | build delle cartelle Kustomize upstream in `kustomize/` |
