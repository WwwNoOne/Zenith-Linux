#!/usr/bin/env bash
# Zenith Linux — comprobación estática del repositorio.
#
#   bash scripts/check-syntax.sh
#
# 1. `bash -n` sobre todos los scripts (los del repo y los del sistema).
# 2. `bash -n` sobre cada bloque RUN del Containerfile (uniendo continuaciones).
# 3. Comprobaciones básicas del Containerfile (continuaciones, COPY de files/).
#
# No necesita Podman. Se usa en local y en GitHub Actions.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail=0
ok()   { printf '  [ OK ]   %s\n' "$*"; }
bad()  { printf '  [ERROR]  %s\n' "$*"; fail=$((fail + 1)); }

echo "== Scripts bash =="
while IFS= read -r f; do
    if bash -n "$f" 2>/dev/null; then
        ok "$f"
    else
        bad "sintaxis en $f"
        bash -n "$f" || true
    fi
done < <(printf '%s\n' build.sh scripts/*.sh \
            files/usr/bin/* files/usr/libexec/zenith/* | sort)

echo
echo "== Bloques RUN del Containerfile =="
PYTHON=""
for cand in python3 python; do
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'raise SystemExit(0)' >/dev/null 2>&1; then
        PYTHON="$cand"
        break
    fi
done
if [[ -z "$PYTHON" ]]; then
    echo "  [info]   sin python3: se omite la comprobación de los RUN"
else
    "$PYTHON" - <<'PY'
import os, re, subprocess, sys, tempfile

cf = "Containerfile"
lines = open(cf, encoding="utf-8").read().split("\n")

bad = 0
# 1. continuaciones rotas
for i, l in enumerate(lines[:-1]):
    if l.rstrip().endswith("\\"):
        nxt = lines[i + 1].strip()
        if nxt == "" or nxt.startswith("#"):
            print(f"  [ERROR]  línea {i + 1}: continuación seguida de vacío o comentario")
            bad += 1

# 2. RUN -> bash -n
blocks, cur = [], None
for l in lines:
    if cur is None:
        if l.startswith("RUN "):
            cur = l[4:]
            if not cur.rstrip().endswith("\\"):
                blocks.append(cur)
                cur = None
        continue
    cur += "\n" + l
    if not l.rstrip().endswith("\\"):
        blocks.append(cur)
        cur = None

td = tempfile.mkdtemp()
for i, b in enumerate(blocks, 1):
    body = b.replace("\\\n", " ")
    p = os.path.join(td, f"run{i}.sh")
    with open(p, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(body + "\n")
    r = subprocess.run(["bash", "-n", p], capture_output=True, text=True)
    if r.returncode == 0:
        print(f"  [ OK ]   RUN {i} ({len(body)} caracteres)")
    else:
        print(f"  [ERROR]  RUN {i}: {r.stderr.strip().splitlines()[0] if r.stderr.strip() else 'fallo'}")
        bad += 1

# 3. contrato mínimo de la imagen
text = "\n".join(lines)
for needle in ("COPY files/ /", "STOPSIGNAL SIGRTMIN+3", 'CMD ["/sbin/init"]'):
    if needle in text:
        print(f"  [ OK ]   {needle}")
    else:
        print(f"  [ERROR]  falta en el Containerfile: {needle}")
        bad += 1

print(f"\n  bloques RUN: {len(blocks)} | errores: {bad}")
sys.exit(1 if bad else 0)
PY
    if (( $? != 0 )); then
        fail=$((fail + 1))
    fi
fi

echo
echo "== Fin de línea (LF) =="
CR=$'\r'
crlf="$(grep -rIl "$CR" Containerfile build.sh scripts files iso 2>/dev/null || true)"
if [[ -z "$crlf" ]]; then
    ok "sin CRLF (los scripts arrancan dentro del contenedor)"
else
    while IFS= read -r f; do
        bad "CRLF en $f (conviértelo a LF)"
    done <<<"$crlf"
fi

echo
if (( fail > 0 )); then
    printf 'Comprobación estática: %d error(es).\n' "$fail"
    exit 1
fi
printf 'Comprobación estática: todo correcto.\n'
