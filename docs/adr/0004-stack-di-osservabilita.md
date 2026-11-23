# ADR 0004 — Stack di osservabilità: kube-prometheus-stack, installato da Flux

- **Data:** 2026-11-20
- **Stato:** accettata; installata e verificata in dev il 2026-11-20 (vedi `docs/observability.md` §8)
- **Collegata a:** ADR 0001 (Prometheus come scelta di metriche), ADR 0003, `docs/gitops.md`

## Contesto

Le metriche esistono già (frontend `/metrics`, `redis_exporter`, fase 5). Servono qualcuno che le raccolga, una dashboard e alert per gli scenari di failure della fase 8. Il nodo è unico e condiviso con dev e prod (requests al 60% di CPU e al 30% di memoria prima dello stack).

## Decisione

- **`kube-prometheus-stack` 93.6.0** come `HelmRelease` di Flux nel namespace `monitoring` (`observability/stack`). Versione fissata nel file.
- **Due Kustomization Flux separate:** `observability-stack` (il chart) e `observability-config` (ServiceMonitor, PrometheusRule, dashboard), la seconda dipende dalla prima perché servono i CRD. **Né dev né prod dipendono dallo stack**, e lo stack non dipende da loro.
- **Prometheus raccoglie tutto:** i selettori di ServiceMonitor e regole sono aperti, non legati all'etichetta `release` del chart.
- **Grafana dietro Ingress** (`grafana.localtest.me`, stesso modello degli altri host); Prometheus e Alertmanager solo con `kubectl port-forward`, perché non hanno autenticazione. Password dell'admin in un Secret cifrato con SOPS.
- **Dashboard come ConfigMap** con l'etichetta `grafana_dashboard: "1"`, caricata dal sidecar di Grafana.
- **NetworkPolicy:** si ammette Prometheus (namespace `monitoring`, pod `app.kubernetes.io/name: prometheus`) verso `frontend:8080` e `redis-cart:9121`. Le altre origini restano escluse.

## Motivazione

- Lo stack include operator, ServiceMonitor, kube-state-metrics e cAdvisor, cioè esattamente ciò che serve per "richieste, latenza, 5xx, restart, Redis" e per gli alert sui pod.
- Tenere dev e prod indipendenti dallo stack evita che un'installazione lenta o rotta (immagini da scaricare, CRD) blocchi il rollout dell'applicazione: era un rischio concreto con `dependsOn` su una Kustomization con `wait: true`.

## Trade-off e limiti

- **Peso:** Prometheus, Grafana, Alertmanager, operator e kube-state-metrics sullo stesso nodo dell'applicazione. Richieste dichiarate: circa 0,4 CPU e 0,9 GiB. **Misurato:** Grafana, con le venti dashboard predefinite del chart, ha usato fino a 4,8 core per circa 15 minuti all'avvio (il 95% del cluster) ed è stato riavviato dalla liveness; le dashboard predefinite sono state disattivate e Grafana ha ora un limite di CPU di 1 core, **che non basta**: aprendo l'app Metrics Drilldown (una query per metrica) Grafana torna al limite e non risponde alle probe; la causa dell'incidente originale non è provata (`docs/observability.md` §8). Il resto dello stack consuma poco (Prometheus circa 65 mCPU e 600 MiB a regime).
- **Nessun volume:** i dati di Prometheus stanno in un `emptyDir` con retention di 2 giorni; si perdono al riavvio del pod. Accettabile per questa challenge, non per un uso reale.
- **Niente node-exporter:** monta `/` dell'host con propagazione, che nei nodi k3d dà errore (problema noto, non provato qui). Conseguenza: nessuna metrica dell'host (disco, rete della VM); restano cAdvisor e kube-state-metrics per i pod.
- **Componenti di k3s non monitorati:** etcd, scheduler, controller-manager e kube-proxy sono disattivati; k3s non li espone sulle porte che il chart si aspetta, e i target risulterebbero "down".
- **Il namespace `monitoring` non ha Pod Security `restricted`** (a differenza di dev e prod): l'operator e i suoi job non sono scritti per quel profilo. Va dichiarato come differenza.
- **Alertmanager senza destinatari:** gli alert si vedono in Prometheus e Alertmanager (UI), non arrivano a nessuno. Il chart include l'alert `Watchdog`, sempre attivo per costruzione.
- **Cardinalità e traffico:** il frontend non conta i 404 né `/_healthz`; la disponibilità non si misura da `frontend_http_requests_total` ma da kube-state-metrics (`docs/observability.md` §1).

## Alternative scartate

- **Solo OpenTelemetry:** meno standard per Kubernetes, nessuna UI né regole pronte (ADR 0001).
- **Stack nel Kustomization `infrastructure` esistente:** dev e prod dipendono da quella, quindi sarebbero rimasti bloccati dall'installazione del chart.
- **Prometheus esposto via Ingress:** nessuna autenticazione; per un laboratorio locale basta il port-forward.
