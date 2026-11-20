# GitOps con Flux

Dalla fase 4 il cluster si modifica **solo da Git**. Flux (controller nel namespace `flux-system`) legge il repository ogni minuto e applica ciò che trova. `scripts/apply-local.sh` non va più usato sul cluster gestito da Flux: i due si contenderebbero gli stessi oggetti.

## 1. Cosa c'è nel cluster

| Oggetto Flux | Segue | Percorso | Note |
|---|---|---|---|
| `GitRepository/flux-system` | branch `main` | — | creato da `flux bootstrap`, accesso con deploy key SSH |
| `Kustomization/flux-system` | `main` | `clusters/local` | gestisce Flux stesso e legge gli altri oggetti da questa cartella |
| `Kustomization/infrastructure` | `main` | `infrastructure/` | oggi solo il namespace `monitoring`; in fase 7 il resto dello stack |
| `Kustomization/boutique-dev` | `main` | `deploy/overlays/dev` | `dependsOn: infrastructure`, decifratura SOPS |
| `GitRepository/boutique-prod` | branch `prod` | — | stessa deploy key, riferimento diverso |
| `Kustomization/boutique-prod` | `prod` | `deploy/overlays/prod` | `dependsOn: infrastructure`, decifratura SOPS |

Tutte le Kustomization hanno `prune: true` (un oggetto tolto da Git viene tolto dal cluster) e `wait: true` (la riconciliazione è "riuscita" solo quando i Deployment sono pronti).

Il Secret `sops-age` (chiave privata age) vive solo nel cluster: lo crea `scripts/flux-bootstrap.sh` da `~/.config/sops/age/keys.txt` e non è mai in Git.

## 2. Installazione

```bash
scripts/cluster-up.sh
GITHUB_TOKEN="$(gh auth token)" scripts/flux-bootstrap.sh   # o un PAT in GITHUB_TOKEN
```

Lo script crea il Secret `sops-age`, poi esegue `flux bootstrap github` (installa i controller, registra la deploy key, committa `clusters/local/flux-system/` su `main`). Il token serve solo per chiamare l'API di GitHub durante il bootstrap: non viene salvato nel cluster né nel repo. È idempotente. Dopo il bootstrap fai `git pull`.

Su un cluster nuovo, Flux applica da solo dev e prod: non serve `apply-local.sh`.

## 3. Promozione

- **dev** segue `main`: un commit (o il merge di una PR) su `main` arriva in dev entro circa un minuto.
- **prod** segue il branch `prod`, che avanza solo con una **PR `main → prod`**. Il merge è l'atto esplicito di promozione.

```bash
gh pr create --base prod --head main --title "Promozione a prod" --body "..."
gh pr merge <numero> --merge
```

Perché un branch e non un tag: Flux sceglie i tag solo con un intervallo semver e il fork contiene i tag upstream (`v0.x`), che verrebbero scambiati per release di prod. Vedi ADR 0003.

**Limite:** oggi "solo con PR" è una convenzione, non un vincolo. Senza branch protection su `prod`, chi ha accesso in scrittura può fare push diretto (e il proprietario può comunque aggirare le regole). Non è stata configurata.

## 4. Rollback e modifiche manuali

- **Rollback corretto:** `git revert <commit>` e push su `main` (o PR su `prod`). Flux riconcilia e riporta lo stato precedente. Provato in dev: il revert di un cambio di repliche ha riportato il Deployment al valore precedente in circa un minuto.
- **`kubectl rollout undo` / `kubectl scale`:** non sono permanenti. Alla prossima riconciliazione (al più 10 minuti, o subito con un nuovo commit) Flux riporta l'oggetto a ciò che dice Git. *Non ancora provato*: è atteso dal modello di Flux, lo si verifica nella fase 8. Per un intervento manuale temporaneo serve `flux suspend kustomization <nome>` e poi `flux resume`.

## 5. Comandi utili

```bash
flux get sources git                       # stato dei repository
flux get kustomizations                    # stato delle Kustomization
flux reconcile kustomization boutique-dev --with-source   # forza subito
flux logs --kind=Kustomization --name=boutique-dev        # errori di build o decifratura
flux suspend kustomization boutique-dev    # ferma la riconciliazione
flux resume kustomization boutique-dev
```

Usa sempre `--context k3d-boutique`: sulla macchina esistono altri contesti Kubernetes.

## 6. Verifiche eseguite (2026-11-19)

| Prova | Esito |
|---|---|
| `flux bootstrap github` sul fork | controller sani, deploy key registrata |
| Decifratura SOPS da parte di Flux (dopo il `kustomize build` con le patch degli overlay) | `redis-cart-auth` in dev e prod: valore di 48 caratteri, non il testo `ENC[...]`; l'oggetto ha l'etichetta di Flux |
| Smoke test dopo la presa in carico di Flux | superato |
| Commit su `main` (frontend a 2 repliche in dev), senza riconciliazione forzata | Deployment a 2 repliche in circa 45 s, nessun `kubectl apply` |
| `git revert` dello stesso commit | torna a 1 replica in circa 55 s |
| `scripts/flux-bootstrap.sh` rieseguito sul cluster esistente | nessuna modifica, tutto sano |

**Non provato:** il bootstrap su un cluster nuovo (`k3d cluster delete` e ripartenza da zero); il drift da modifica manuale; la promozione a prod: la PR #1 `main → prod` è stata aperta ma **non fatta il merge**, quindi non è verificato che Flux aggiorni prod dopo il merge (prod è ferma a `prod@1985157e`).
