# krateo/ — artefatti della valutazione (fase 9)

Tutto qui è **concettuale**: nessun file è stato applicato a un cluster Krateo. Cosa è stato controllato e cosa no sta in [`docs/krateo-evaluation.md`](../docs/krateo-evaluation.md) §4.

| File | Cosa è |
|---|---|
| `boutique-environment/` | chart wrapper: con `values.schema.json` (requisito di Krateo) e due template Flux (`GitRepository`, `Kustomization`) |
| `compositiondefinition.yaml` | come il chart verrebbe registrato come API (`CompositionDefinition`) |
| `composition.example.yaml` | un'istanza (`Composition`) di esempio: un ambiente `prod` di tier `critical` |

Controlli eseguibili senza Krateo (quelli fatti il 2026-11-23):

```bash
helm lint krateo/boutique-environment
helm template demo krateo/boutique-environment --set tier=gold      # deve fallire: tier fuori dall'enum
helm template demo krateo/boutique-environment | kubeconform -strict -summary \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```
