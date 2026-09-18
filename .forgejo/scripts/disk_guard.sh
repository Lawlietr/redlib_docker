#!/bin/bash
set -euo pipefail

# The runner host has only 10GB of disk. A redlib build peaks at ~4.5-5.5G
# extra (base image pull + clone + cargo), and the Tier-2 BuildKit cargo
# caches (~3-4G) persist between builds. Fail fast if free space is too low
# so a build can never fill the disk.
MIN_AVAIL_KB=2560000 # 2.5G

avail_kb=$(df --output=avail -k / | tail -1 | tr -d '[:space:]')
echo "Disk free: ${avail_kb} KB (minimum: ${MIN_AVAIL_KB} KB)"

if [ "$avail_kb" -lt "$MIN_AVAIL_KB" ]; then
	echo "ERROR: free disk below ${MIN_AVAIL_KB} KB — aborting to protect the host disk." >&2
	exit 1
fi
