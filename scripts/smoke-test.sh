#!/usr/bin/env bash
# Prova i percorsi principali dello shop attraverso l'Ingress.
# Uso: scripts/smoke-test.sh [base_url]
# Default: http://boutique-dev.localtest.me:8080
set -euo pipefail

BASE_URL="${1:-http://boutique-dev.localtest.me:8080}"
JAR="$(mktemp)"
trap 'rm -f "$JAR"' EXIT
fail=0

# check <descrizione> <codice atteso> <curl args...>
check() {
  local desc="$1" expected="$2"; shift 2
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -b "$JAR" -c "$JAR" "$@" || true)"
  if [ "$code" = "$expected" ]; then
    echo "OK    $desc ($code)"
  else
    echo "FAIL  $desc: atteso $expected, ottenuto $code"
    fail=1
  fi
}

check "health frontend"        200 "$BASE_URL/_healthz"
check "home (catalogo)"        200 "$BASE_URL/"
check "pagina prodotto"        200 "$BASE_URL/product/OLJCESPC7Z"
check "cambio valuta"          302 -X POST -d "currency_code=EUR" "$BASE_URL/setCurrency"
check "aggiunta al carrello"   302 -X POST -d "product_id=OLJCESPC7Z" -d "quantity=1" "$BASE_URL/cart"
check "vista carrello"         200 "$BASE_URL/cart"
check "checkout (intera catena)" 200 -X POST \
  -d "email=test@example.com" -d "street_address=1600 Amphitheatre Parkway" \
  -d "zip_code=94043" -d "city=Mountain View" -d "state=CA" -d "country=United States" \
  -d "credit_card_number=4432801561520454" -d "credit_card_expiration_month=1" \
  -d "credit_card_expiration_year=2099" -d "credit_card_cvv=672" \
  "$BASE_URL/cart/checkout"

if [ "$fail" -eq 0 ]; then echo "Smoke test superato."; else echo "Smoke test FALLITO." >&2; exit 1; fi
