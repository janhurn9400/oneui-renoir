#!/usr/bin/env bash
# Run a shell snippet (stdin or args) as root inside the Parallels Ubuntu VM.
# The project is shared into the VM at /media/psf/Home/Desktop/ROMS/oneui-renoir ($P inside the snippet).
# Usage: tools/vm.sh 'cmd ...'   or   tools/vm.sh < script.sh
set -euo pipefail
VM="${VM:-Ubuntu 26.04 (with Rosetta)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/work/.vm"
f="$ROOT/work/.vm/run-$$.sh"
{
  echo 'set -e'
  echo 'export P=/media/psf/Home/Desktop/ROMS/oneui-renoir'
  echo 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
  if [ $# -gt 0 ]; then echo "$*"; else cat; fi
} > "$f"
trap 'rm -f "$f"' EXIT
# Prefer SSH (stable); fall back to prlctl exec (joins args into one line, flaky, shared-folder lag).
KEY="$HOME/.ssh/nothing-renoir-vm"; HOST="${VM_HOST:-10.211.55.6}"
if [ -f "$KEY" ] && ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=3 "root@$HOST" true 2>/dev/null; then
  ssh -i "$KEY" -o BatchMode=yes "root@$HOST" bash -s < "$f"
else
  sleep 2
  prlctl exec "$VM" bash "/media/psf/Home/Desktop/ROMS/oneui-renoir/work/.vm/$(basename "$f")"
fi
