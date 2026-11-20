// Modifica rispetto a upstream (fase 5 del piano di lavoro): metriche Prometheus
// del frontend. Vedi docs/observability.md.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gorilla/mux"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	// L'etichetta "route" è il template del percorso (es. /product/{id}), non l'URL
	// reale: tiene bassa la cardinalità. Le richieste che non corrispondono a nessuna
	// route (404) non passano dal middleware e quindi non sono contate.
	httpRequestsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "frontend_http_requests_total",
		Help: "Richieste HTTP gestite dal frontend, per metodo, route e codice di stato.",
	}, []string{"method", "route", "code"})

	httpRequestDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "frontend_http_request_duration_seconds",
		Help:    "Durata delle richieste HTTP del frontend, per metodo e route.",
		Buckets: []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10},
	}, []string{"method", "route"})
)

// metricsMiddleware è un middleware di mux: gira dopo il routing, quindi può leggere
// il template della route. Le probe (/_healthz) sono escluse, altrimenti dominerebbero
// il traffico misurato.
func metricsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		route := "unknown"
		if cr := mux.CurrentRoute(r); cr != nil {
			if tpl, err := cr.GetPathTemplate(); err == nil {
				route = tpl
			}
		}
		if route == baseUrl+"/_healthz" {
			next.ServeHTTP(w, r)
			return
		}

		start := time.Now()
		rr := &responseRecorder{w: w}
		next.ServeHTTP(rr, r)

		status := rr.status
		if status == 0 { // handler che non ha scritto nulla: net/http risponde 200
			status = http.StatusOK
		}
		httpRequestsTotal.WithLabelValues(r.Method, route, strconv.Itoa(status)).Inc()
		httpRequestDuration.WithLabelValues(r.Method, route).Observe(time.Since(start).Seconds())
	})
}

// withMetricsEndpoint serve /metrics prima degli altri middleware, così la scrape di
// Prometheus non genera cookie di sessione, log di richiesta né span di tracing.
func withMetricsEndpoint(next http.Handler) http.Handler {
	metrics := promhttp.Handler()
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == baseUrl+"/metrics" {
			metrics.ServeHTTP(w, r)
			return
		}
		next.ServeHTTP(w, r)
	})
}
