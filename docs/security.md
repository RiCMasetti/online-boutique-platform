# Sicurezza e hardening

Cosa è stato fatto nella fase 3, come è stato verificato e cosa **non** è coperto. Gli ambienti sono `boutique-dev` e `boutique-prod`, nello stesso cluster k3d.

## 1. Misure applicate

| Misura | Dove | Verificato come |
|---|---|---|
| Token del service account non montato (`automountServiceAccountToken: false`) su ServiceAccount e pod | [deploy/base/kustomization.yaml](../deploy/base/kustomization.yaml) | I pod risultano con `automountServiceAccountToken: false` e senza volume `kube-api-access`. Prima: nessun servizio usa l'API Kubernetes (nessun client K8s nelle dipendenze di `src/`). |
| ServiceAccount dedicato per `redis-cart` | [deploy/base/redis-serviceaccount.yaml](../deploy/base/redis-serviceaccount.yaml) | Upstream ne definisce 11 (uno per servizio) ma non per Redis. |
| `seccompProfile: RuntimeDefault` su tutti i pod | base | Presente nei 12 pod; accettato da PSA `restricted`. |
| Contesto di sicurezza già presente upstream: `runAsNonRoot`, `readOnlyRootFilesystem`, `drop: ALL`, `allowPrivilegeEscalation: false` | `kustomize/base` (non modificato) | Letto nei manifest. Redis gira come `uid=1000`. **Nessuna eccezione** da documentare: tutti i container lo rispettano. |
| Pod Security Admission `restricted` in modalità `enforce` sui due namespace | `namespace.yaml` degli overlay | Dry-run lato server prima di adottarlo (nessuna violazione). Controllo negativo: un pod `--privileged` in `boutique-dev` viene rifiutato. |
| NetworkPolicy: `deny-all` più una policy per servizio (component upstream) | [deploy/components/network-policies](../deploy/components/network-policies/kustomization.yaml) | `scripts/netpol-test.sh`, vedi sotto. |
| Ingress del frontend limitato a Traefik e al loadgenerator (upstream accetta tutto) | stesso component | Stesso test. |
| Password Redis (`requirepass`) in un Secret cifrato con SOPS+age, diversa per dev e prod | `deploy/overlays/*/redis-auth.enc.yaml` | `redis-cli ping` senza password risponde `NOAUTH`; lo shop funziona (cartservice si autentica); i test funzionali passano in dev e prod. |

### Verifica delle NetworkPolicy

`scripts/netpol-test.sh [namespace]` lancia pod usa-e-getta con la label di un servizio e prova connessioni TCP: tre percorsi previsti devono riuscire (frontend → cartservice, cartservice → Redis, loadgenerator → frontend solo in dev), sei non previsti devono essere bloccati, più un tentativo dall'altro ambiente. Il test è stato reso robusto dopo aver trovato un difetto: se il pod non partiva, il caso veniva contato come "bloccato". Ora il pod deve stampare l'esito di `nc`, altrimenti è un errore.

Controlli negativi eseguiti (k3s applica le policy davvero):
- senza la policy di `cartservice`, i percorsi leciti verso di lui vengono bloccati dal `deny-all` (il test fallisce);
- senza `deny-all` **e** senza la policy di `cartservice`, `emailservice` e un pod dell'altro ambiente raggiungono `cartservice:7070` (il test fallisce sui casi "bloccato").

## 2. Gestione dei secret (SOPS + age)

**Caso costruito per la challenge.** L'app non ha secret reali. La password di Redis è stata introdotta apposta per mostrare il flusso: `redis-cart` parte con `--requirepass` e `cartservice` la riceve nella stringa di connessione.

- `.sops.yaml` (nel repo) contiene solo la chiave **pubblica** age e cifra i campi `data`/`stringData` dei file `deploy/**/*.enc.yaml`.
- La chiave **privata** è in `~/.config/sops/age/keys.txt` (permessi 600), **fuori dal repo**. Non va mai committata né incollata in prompt o log. `.gitignore` esclude `keys.txt`, `*.agekey`, `age.key` e `*.dec.yaml`.
- Le password sono state generate con `openssl rand -hex 24` e cifrate senza mai passare dall'output. Dev e prod hanno valori diversi.
- Per creare un Secret nuovo: scrivi il file in chiaro **fuori dal repo**, cifralo con `sops --encrypt --filename-override deploy/overlays/<env>/<nome>.enc.yaml ...`, elimina il file in chiaro.
- **Con Flux (fase 4)** i Secret li decifra il controller; `scripts/apply-local.sh <dev|prod>` (decifra con la chiave locale e passa a `kubectl` via pipe) serve solo su un cluster senza Flux e non va usato insieme a Flux.

**Custodia della chiave.** Se si perde `keys.txt`, i Secret nel repo non sono più decifrabili e vanno rigenerati. Va fatto un backup fuori dal repo. Ogni cluster nuovo ha bisogno della stessa chiave (in Flux è il Secret `sops-age` in `flux-system`, creato da `scripts/flux-bootstrap.sh` a partire dal file locale e mai committato).

### Chi fa cosa: SOPS, Kustomize e Flux

**Kustomize non integra SOPS.** `.sops.yaml` è letto solo dal programma `sops` quando si cifra; Kustomize e Flux non lo usano.

| Fase | Chi agisce | Cosa usa |
|---|---|---|
| Cifratura | `sops --encrypt` | `.sops.yaml`: la regola con `path_regex` sceglie la chiave pubblica age e i campi da cifrare (`data`, `stringData`). Il nome del file deve corrispondere a `deploy/.*\.enc\.yaml$` (per questo si usa `--filename-override`). |
| Build | `kustomize build` | Tratta `redis-auth.enc.yaml` come un normale Secret in `resources:`. La chiave `sops:` in più (destinatario age e MAC) passa inalterata. |
| Decifratura | il controller Flux (`spec.decryption` delle Kustomization); senza Flux, `scripts/apply-local.sh` con `sops --decrypt` | Il blocco `sops:` dentro il file e la **chiave privata**. Non `.sops.yaml`. |

Conseguenze pratiche:
- `kubectl apply -k` non è utilizzabile sugli overlay: applicherebbe il testo cifrato come valore del Secret (da qui `apply-local.sh`, che decifra e applica via pipe).
- `kubeconform -strict` rifiuta il Secret cifrato per la chiave sconosciuta `sops`: nella validazione va escluso (`-skip Secret`).
- Con Flux le `Kustomization` `boutique-dev` e `boutique-prod` dichiarano `spec.decryption: {provider: sops, secretRef: {name: sops-age}}` e il controller decifra con la chiave privata presente nel cluster.
- **Verificato in fase 4:** Flux decifra `redis-cart-auth` dopo il `kustomize build` con le patch degli overlay (valore in chiaro di 48 caratteri in dev e prod). Non è stata riletta la documentazione di Flux sull'ordine build/decifratura: la prova è empirica.
- Esiste KSOPS, un generatore che integra SOPS dentro Kustomize con un plugin esterno. Non è adottato: per questo progetto la decifratura nativa di Flux è più semplice.

## 3. Limiti residui

Dichiarati apertamente: non sono difetti nascosti, ma confini di ciò che è stato fatto.

**Rete**
- **L'uscita non è limitata.** Le policy upstream hanno `egress: [{}]`: un pod compromesso può contattare qualunque destinazione. Le policy restringono solo l'ingresso.
- Il traffico gRPC interno è in chiaro (nessun mTLS, nessun service mesh).
- Quando arriveranno Prometheus e gli exporter (fasi 5-7) servirà aprire l'ingresso verso `frontend:8080` e verso gli exporter: va aggiornata la policy.

**Secret e Redis**
- Redis è una sola replica, senza TLS e senza persistenza (`emptyDir`): i carrelli si perdono al ricreare del pod.
- La password è passata come argomento (`--requirepass $(REDIS_PASSWORD)`) e come parte di `REDIS_ADDR` in `cartservice`: i manifest non la contengono, ma è visibile a chi può eseguire comandi nel pod (`ps`, `env`).
- Nessuna rotazione dei secret. Una sola chiave age serve entrambi gli ambienti: in un caso reale servirebbero chiavi separate per ambiente.
- Per default k3s non cifra i Secret a riposo in etcd (da verificare nella documentazione di k3s prima di affermarlo nel documento finale). Chi accede al nodo li legge.

**Ambienti e immagini**
- `dev` e `prod` condividono cluster, nodo e control plane: nessun isolamento reale (ADR 0001). L'isolamento di rete tra i namespace è verificato, quello di risorse no.
- Le immagini sono upstream, senza firma e fissate per tag (non per digest); `redis:alpine` non ha un tag fissato. Con le immagini multi-arch proprie (ADR 0002) si potrà fissare per digest e scansionare con Trivy (fase 6).
- Il workaround per arm64 (probe liveness con ritardo di 60 s e timeout di 5 s, limiti di memoria a 256Mi) è in `deploy/components/arm64-workaround` e **indebolisce** il rilevamento dei guasti in entrambi gli ambienti. Scompare con le immagini multi-arch.

**Processo**
- PSA `restricted` rifiuta qualunque pod futuro non conforme (per esempio un exporter come sidecar senza `securityContext`): va tenuto conto nelle fasi 5-7.
- Il file `.sops.yaml` e la chiave pubblica sono pubblici per costruzione; i metadati dei Secret (nome, namespace) restano in chiaro.
