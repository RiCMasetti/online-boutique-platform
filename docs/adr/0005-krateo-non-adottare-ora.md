# ADR 0005 — Krateo: non adottarlo ora, tenere il blueprint

- **Data:** 2026-11-23
- **Stato:** accettata (proposta dell'AI, da confermare da me); vedi `docs/krateo-evaluation.md`
- **Collegata a:** ADR 0001 (Flux come motore GitOps), ADR 0003

## Contesto

La traccia chiede di valutare Krateo. Ho letto la documentazione 3.0.0 e disegnato un chart wrapper (`krateo/boutique-environment/`) che trasforma "nuovo ambiente Boutique" in una `Composition` con 8 parametri validati. Il chart passa i controlli statici, ma **non è stato provato in un cluster Krateo**.

## Decisione

- **Non adottare Krateo** in questo progetto. Si consegna un **blueprint**, non un PoC.
- Se in futuro si procede: Krateo possiede solo gli oggetti Flux di un ambiente; Flux resta il motore che applica l'app (nessun doppio controllo sullo stesso oggetto).

## Motivazione

- La doc dichiara come minimo 12 vCPU e 16 GiB per la piattaforma (con PostgreSQL CNPG). Il nodo del progetto ha 6 CPU e 9,7 GiB, già al 56% di memoria.
- Con un solo operatore e un solo team, il valore del self-service è basso rispetto ai pezzi aggiunti.
- La compatibilità Krateo + Flux non è documentata nelle pagine lette (gli esempi usano Argo CD): è l'incognita principale.

## Trade-off e limiti

- Si rinuncia a un portale e a permessi minimi automatici per ambiente.
- La decisione si regge su un'assenza di prove (nessun PoC): si rivede se il PoC su un cluster separato dà esito positivo.
- Resta da costruire, in ogni caso, l'overlay parametrico `environment-*` (non esiste).

## Alternative scartate

- **PoC sul cluster della demo:** rischio concreto per la stabilità (Grafana ha già portato il nodo al limite).
- **Adozione piena:** non giustificata dai numeri sopra.
- **Argo CD al posto di Flux per usare gli esempi della doc:** contraddice ADR 0001 e rimette in discussione il lavoro delle fasi 4-8.
