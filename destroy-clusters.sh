#!/bin/bash
set -euo pipefail

NUM_CLUSTERS_TO_KEEP=${1:-"0"}
LOOKUP_DIR=${LOOKUP_DIR:-"./clusters"}
CLUSTER_PREFIX=${CLUSTER_PREFIX:-"$(whoami)-"}

echo "Removing all clusters except for last" "$NUM_CLUSTERS_TO_KEEP"
echo "Looking up cluster directories from" "$LOOKUP_DIR"

CLUSTER_DIRS=$(find "$LOOKUP_DIR" -maxdepth 1 -name "$CLUSTER_PREFIX""*" -type d -printf "%T@ %p\n" | sort | head -n -"$NUM_CLUSTERS_TO_KEEP" | cut -d " " -f2)
echo "This operation is about to destroy" "$(echo "${CLUSTER_DIRS}" | wc -l)" "cluster(s)!!"
read -r -n 1 -p "Press any key to continue..."

for CLUSTER_DIR in $CLUSTER_DIRS
do
    echo "Prepare to destroy cluster:" "'$CLUSTER_DIR'"
    if ./openshift-install destroy cluster --dir "$CLUSTER_DIR" --log-level debug; then
        rm -rf "$CLUSTER_DIR" "$CLUSTER_DIR"".log"
    fi
done
