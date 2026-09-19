#!/bin/bash
set -euo pipefail

# The runner host has 30GB of disk (originally 10GB, expanded 2026-09-18).
# A multi-arch redlib build peaks at ~5-6G extra (base image pull + clone +
# cargo), and the Tier-2 BuildKit cargo caches (~3-4G) persist between builds.
# Fail fast if free space drops below the floor so a build can never fill the
# disk. 6G floor matches the guard documented in the design files.
MIN_AVAIL_KB=6144000 # 6G safety floor

# NOTE: the job runs inside the Alpine/BusyBox runner image — `df --output`
# is GNU-only and fails there; `df -P` (1024-byte blocks, POSIX columns) +
# awk is the portable form. Field 4 = Available.
avail_kb=$(df -P / | awk 'NR==2 {print $4}')
echo "Disk free: ${avail_kb} KB (minimum: ${MIN_AVAIL_KB} KB)"

if [ "$avail_kb" -lt "$MIN_AVAIL_KB" ]; then
	echo "ERROR: free disk below ${MIN_AVAIL_KB} KB — aborting to protect the host disk." >&2
	exit 1
fi
