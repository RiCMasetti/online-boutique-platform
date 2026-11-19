# GitHub Actions Workflows

Questo fork usa un sottoinsieme dei workflow upstream. I workflow che si autenticavano sul progetto Google Cloud di upstream (deploy su GKE, cleanup, release) sono stati rimossi perché non possono funzionare su un fork. Restano nella history e nel remote `upstream`.

| Workflow | Cosa fa |
|---|---|
| [ci-pr.yaml](ci-pr.yaml) | Test unitari Go e C# su ogni pull request verso `main` |
| [ci-main.yaml](ci-main.yaml) | Gli stessi test su ogni push su `main` e `release/*` |
| [kustomize-build-ci.yaml](kustomize-build-ci.yaml) | Build delle base Kustomize upstream. Sarà sostituito dalla CI del progetto (fase 6) |

La CI di piattaforma (lint, `kubeconform`, build e push su GHCR) viene aggiunta nella fase 6 del piano di lavoro.
