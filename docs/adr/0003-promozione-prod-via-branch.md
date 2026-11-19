# ADR 0003 — Promozione a prod tramite branch dedicato

- **Data:** 2026-11-19
- **Stato:** accettata
- **Collegata a:** ADR 0001, `docs/gitops.md`

## Contesto

Con Flux, `dev` deve seguire `main` e `prod` deve cambiare solo per una scelta esplicita (PR o tag). Esiste un solo repository e un solo cluster.

## Decisione

`prod` ha un `GitRepository` dedicato (`boutique-prod`) che segue il branch **`prod`**. Il branch avanza con una PR `main → prod`. Le Kustomization `boutique-dev` e `boutique-prod` leggono dallo stesso repository ma da riferimenti diversi.

## Motivazione

- La promozione è una PR: revisionabile, con storia leggibile e annullabile con `git revert`.
- Funziona con gli strumenti già presenti (Git, `gh`), senza ulteriori componenti.

## Trade-off

- **Non è un vincolo tecnico:** senza branch protection, chiunque abbia accesso in scrittura può fare push su `prod`. Va dichiarato come limite; la protezione del branch non è configurata.
- **Storia divisa:** i merge su `prod` creano commit che non esistono su `main`. Accettabile per questo progetto.
- **Il branch `prod` contiene tutto il repository,** non solo `deploy/overlays/prod`: la separazione è nel percorso letto da Flux, non nel contenuto.

## Alternative scartate

- **Tag con `ref.semver`:** la promozione sarebbe un tag immutabile (più pulito), ma Flux seleziona i tag solo con un intervallo semver e il fork contiene i tag upstream (`v0.8.1`, `v0.9.0`, ...): prod si aggancerebbe alla release upstream più recente, che non contiene `deploy/`. Si potrebbe usare una convenzione di nomi dedicata; non vale la complessità per ora.
- **Due repository o due cluster:** separazione più forte, costo sproporzionato per questa challenge (vedi ADR 0001).
