package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gorilla/mux"
	"github.com/prometheus/client_golang/prometheus/testutil"
)

func newTestHandler() http.Handler {
	r := mux.NewRouter()
	r.HandleFunc("/product/{id}", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })
	r.HandleFunc("/boom", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusInternalServerError) })
	r.HandleFunc("/_healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })
	r.Use(metricsMiddleware)
	return withMetricsEndpoint(r)
}

func do(h http.Handler, method, path string) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(method, path, nil))
	return rec
}

func TestMetricsUseRouteTemplateAndStatus(t *testing.T) {
	h := newTestHandler()
	before200 := testutil.ToFloat64(httpRequestsTotal.WithLabelValues("GET", "/product/{id}", "200"))
	before500 := testutil.ToFloat64(httpRequestsTotal.WithLabelValues("GET", "/boom", "500"))

	do(h, http.MethodGet, "/product/AAA")
	do(h, http.MethodGet, "/product/BBB") // stessa route, id diverso: stessa serie
	do(h, http.MethodGet, "/boom")

	if got := testutil.ToFloat64(httpRequestsTotal.WithLabelValues("GET", "/product/{id}", "200")) - before200; got != 2 {
		t.Errorf("route /product/{id} 200: attese 2 richieste, trovate %v", got)
	}
	if got := testutil.ToFloat64(httpRequestsTotal.WithLabelValues("GET", "/boom", "500")) - before500; got != 1 {
		t.Errorf("route /boom 500: attesa 1 richiesta, trovate %v", got)
	}
}

func TestHealthzExcluded(t *testing.T) {
	h := newTestHandler()
	before := testutil.ToFloat64(httpRequestsTotal.WithLabelValues("GET", "/_healthz", "200"))
	do(h, http.MethodGet, "/_healthz")
	if got := testutil.ToFloat64(httpRequestsTotal.WithLabelValues("GET", "/_healthz", "200")) - before; got != 0 {
		t.Errorf("/_healthz non dovrebbe essere contata, trovate %v", got)
	}
}

func TestMetricsEndpointExposesSeries(t *testing.T) {
	h := newTestHandler()
	do(h, http.MethodGet, "/product/CCC")
	rec := do(h, http.MethodGet, "/metrics")
	if rec.Code != http.StatusOK {
		t.Fatalf("/metrics: status %d", rec.Code)
	}
	body := rec.Body.String()
	for _, want := range []string{
		`frontend_http_requests_total{code="200",method="GET",route="/product/{id}"}`,
		"frontend_http_request_duration_seconds_bucket",
	} {
		if !strings.Contains(body, want) {
			t.Errorf("/metrics non contiene %q", want)
		}
	}
	if c := rec.Header().Get("Set-Cookie"); c != "" {
		t.Errorf("/metrics non deve impostare cookie, trovato %q", c)
	}
}
