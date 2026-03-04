#!/bin/bash
# Migrate ergo/incore data files from incore-prod to microk8s
# Run from tmp/ with: bash ../migrate-data-copy.sh

set -e
PROD_POD=$(kubectl get pods -n incore --context incore-prod -l app.kubernetes.io/name=incore-svc-data -o jsonpath='{.items[0].metadata.name}')
MICROK8S_POD=$(kubectl get pods -n incore --context microk8s -l app.kubernetes.io/name=incore-svc-data -o jsonpath='{.items[0].metadata.name}')

[[ -z "$PROD_POD" ]] && { echo "ERROR: No incore-prod data pod"; exit 1; }
[[ -z "$MICROK8S_POD" ]] && { echo "ERROR: No microk8s data pod"; exit 1; }
[[ ! -f ergo-incore-paths.txt ]] && { echo "ERROR: Run Step 1 first to create ergo-incore-paths.txt"; exit 1; }

mkdir -p migration-data/data
count=0
fail=0

while IFS= read -r path || [[ -n "$path" ]]; do
  path=$(echo "$path" | tr -d '\r')
  [[ -z "$path" ]] && continue
  # Strip leading /home/incore/data/ if present (some dataURLs have full path)
  path="${path#/home/incore/data/}"
  [[ -z "$path" ]] && continue

  parent_dir=$(dirname "$path")
  dir_name=$(basename "$path")
  mkdir -p "migration-data/data/$parent_dir"

  # Copy from prod: source is the directory, dest is parent so we get dir_name inside
  if ! kubectl cp "incore/${PROD_POD}:/home/incore/data/${path}" "migration-data/data/${parent_dir}/" --context incore-prod 2>/dev/null; then
    echo "FAIL prod: $path"
    ((fail++)) || true
    continue
  fi

  # Copy to microk8s: we have migration-data/data/parent_dir/dir_name, copy that to pod
  # kubectl cp with dir: copies dir into destination. We need /home/incore/data/parent_dir/dir_name on pod
  if ! kubectl cp "migration-data/data/${parent_dir}/${dir_name}" "incore/${MICROK8S_POD}:/home/incore/data/${parent_dir}/" --context microk8s 2>/dev/null; then
    echo "FAIL microk8s: $path"
    ((fail++)) || true
    continue
  fi

  ((count++))
  [[ $((count % 100)) -eq 0 ]] && echo "  Copied $count..."
done < ergo-incore-paths.txt

echo "Done. Copied $count paths, $fail failed."
echo ""
echo "Verify: kubectl exec -n incore deployment/incore-svc-data --context microk8s -- sh -c 'find /home/incore/data -type f | wc -l'"
