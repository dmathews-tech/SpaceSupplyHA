#!/usr/bin/env bash
set -euo pipefail

IP="${1:-}"
PASS="${2:-${PJLINK_PASSWORD:-}}"

if [[ -z "$IP" ]]; then
  exit 1
fi

python3 - "$IP" "$PASS" <<'PY'
import hashlib, re, socket, sys
ip = sys.argv[1]
password = sys.argv[2]

def fail():
    print("")
    sys.exit(0)

try:
    s = socket.create_connection((ip, 4352), timeout=4)
    banner = s.recv(1024).decode(errors="ignore").strip()
    if not banner.startswith("PJLINK"):
        fail()

    cmd = "%1LAMP ?\r"
    if banner.startswith("PJLINK 1"):
        parts = banner.split()
        if len(parts) < 3:
            fail()
        nonce = parts[2]
        if not password:
            fail()
        digest = hashlib.md5((password + nonce).encode()).hexdigest()
        payload = (digest + cmd).encode()
    else:
        payload = cmd.encode()

    s.sendall(payload)
    resp = s.recv(1024).decode(errors="ignore").strip()
    s.close()

    # %1LAMP=1234 0  (hour + on/off pairs)
    m = re.search(r"%1LAMP=([0-9]+)", resp)
    if not m:
        fail()
    print(m.group(1))
except Exception:
    fail()
PY
