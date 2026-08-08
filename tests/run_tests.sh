#!/bin/bash
# ====================================================================
# EALN-64 Test Harness (zero-libc, native ARM64)
#   ./run_tests.sh                 -> solo tests
#   ./run_tests.sh --measure       -> + reporte de densidad (bytes/opcodes/tokens)
#
# Cada caso: <nombre>.esp con expected en <nombre>.expected
# Compatibilidad cross: exporta QEMU=qemu-aarch64-static para ejecutar
# los binarios generados bajo emulación (usado en CI x86_64).
# ====================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
MEASURE=0
[ "${1:-}" = "--measure" ] && MEASURE=1

# Buildea el compilador (as + ld, zero C)
echo ">>> Building ealn-compiler..."
make clean >/dev/null 2>&1 || true
make >/dev/null 2>&1
if [ ! -x ./ealn-compiler ]; then
  echo "ERROR: compilador no generado" >&2; exit 1
fi

# Wrapper para ejecutar salida.out: usa QEMU si está definido (cross),
# o ejecuta directamente en host native (arm64).
QEMU="${QEMU:-}"
run_bin() {
  if [ -n "$QEMU" ]; then "$QEMU" "$ROOT/salida.out" 2>/dev/null
  else "$ROOT/salida.out"; fi
}

TOTAL=0; PASS=0; FAIL=0
echo "=== TEST SUITE ==="
for fuente in tests/cases/*.esp; do
  base="$(basename "$fuente" .esp)"
  # Excluir archivos temporales de debug
  case "$base" in dbg*) continue;; esac
  expected="$ROOT/tests/cases/$base.expected"
  TOTAL=$((TOTAL+1))
  # Compila pasando el fuente como argv[1] (test aislado)
  if ! ./ealn-compiler "$fuente" >/dev/null 2>&1; then
    echo "[FAIL] $base: error de compilación"; FAIL=$((FAIL+1)); continue
  fi
  out=$(run_bin; rc=$?) 2>/dev/null; rc=$?
  if [ $MEASURE -eq 1 ]; then
    bytes=$(stat -c%s "$ROOT/salida.out" 2>/dev/null || echo "?")
    # Contar opcodes: salida.out es raw, ~4 bytes/opcode (header excluido)
    opcodes=$(( (bytes - 120) / 4 ))
    [ "$opcodes" -lt 0 ] && opcodes=0
    echo "[MEASURE] $base: binario=$bytes bytes | opcodes≈$opcodes | rc=$rc"
  fi
  if [ -f "$expected" ]; then
    want="$(cat "$expected")"
    if [ "$out" = "$want" ]; then
      echo "[PASS] $base: '$out'"; PASS=$((PASS+1))
    else
      echo "[FAIL] $base: got='$out' want='$want'"; FAIL=$((FAIL+1))
    fi
  else
    echo "[SKIP] $base: no hay .expected | rc=$rc salida='$out'"
  fi
done
echo "=== RESULTADO: $PASS/$TOTAL PASS, $FAIL FAIL ==="
[ $FAIL -eq 0 ]
