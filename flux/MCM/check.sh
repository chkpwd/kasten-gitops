#!/usr/bin/env bash
# Offline check for charts/kasten-mc and the Flux stages. No cluster needed.
# Renders every stage the way its HelmRelease does, then checks that bad
# values fail. Run: flux/MCM/check.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

host=--set=k10.route.host=k10.example.invalid
p=flux/MCM/clusters/ocp-primary
s=flux/MCM/clusters/ocp-secondary
sr=flux/MCM/clusters/ocp-secondary

# Render one HelmRelease file: its valuesFiles, then its inline values.
render() {
  local hr=$1; shift
  local args=() f
  while read -r f; do args+=(-f "$f"); done < <(yq '.spec.chart.spec.valuesFiles[]' "$hr")
  helm template "$(yq '.spec.releaseName' "$hr")" "$(yq '.spec.chart.spec.chart' "$hr")" \
    -n "$(yq '.spec.targetNamespace' "$hr")" "${args[@]}" -f <(yq '.spec.values' "$hr") "$@"
}

ok()   { render "$@" >/dev/null || { echo "FAIL: expected $1 to render"; exit 1; }; }
fails() { local want=$1; shift
  if out=$(render "$@" 2>&1 >/dev/null); then echo "FAIL: expected an error ($want)"; exit 1; fi
  grep -q "$want" <<<"$out" || { echo "FAIL: wrong error, wanted '$want': $out"; exit 1; }; }

helm dependency build flux/MCM/charts/kasten-mc >/dev/null

ok "$p/kasten.yaml"
ok "$p/handoff.yaml" "$host"
ok "$s/kasten.yaml"
ok "$sr/pull/helmrelease.yaml"
ok "$sr/join/helmrelease.yaml" "$host"

fails "Cannot find the Kasten dashboard URL" "$sr/join/helmrelease.yaml"
fails "global.kastenMc.role" "$p/kasten.yaml" --set global.kastenMc.role=
fails "only on the secondary" "$p/handoff.yaml" "$host" --set handoff.pull.enabled=true
fails "must be a full URL" "$sr/join/helmrelease.yaml" --set handoff.join.clusterIngress=https://k10.example.invalid
fails "needs handoff.token.enabled" "$p/handoff.yaml" "$host" --set handoff.token.enabled=false

# A custom secret name must reach both the push and the pull.
render "$p/handoff.yaml" "$host" --set handoff.remoteKey=kasten/prod/join-token \
  | yq -e 'select(.kind == "PushSecret") | .spec.data[0].match.remoteRef.remoteKey == "kasten/prod/join-token"' >/dev/null
render "$sr/pull/helmrelease.yaml" --set handoff.remoteKey=kasten/prod/join-token \
  | yq -e 'select(.kind == "ExternalSecret") | .spec.data[0].remoteRef.key == "kasten/prod/join-token"' >/dev/null

# Dashboard URL from the k10 Route or Ingress values.
url() { render "$sr/join/helmrelease.yaml" "$@" | yq 'select(.kind == "ConfigMap") | .data.cluster-ingress'; }
want() { local w=$1; shift; got=$(url "$@"); [ "$got" = "$w" ] || { echo "FAIL: wanted $w, got $got"; exit 1; }; }
want https://k10.example.invalid/k10 "$host"
want https://k10.example.invalid/backup "$host" --set k10.route.path=/backup/
ing=(--set k10.route.enabled=false --set k10.ingress.create=true --set k10.ingress.host=k10.example.invalid)
want http://k10.example.invalid/k10 "${ing[@]}"
want https://k10.example.invalid/kasten "${ing[@]}" --set k10.ingress.tls.enabled=true --set k10.ingress.urlPath=kasten

# Rotation: the PushSecret must follow the new token Secret.
render "$p/handoff.yaml" "$host" --set handoff.token.generation=2 \
  | yq -e 'select(.kind == "PushSecret") | .spec.selector.secret.name == "kasten-mc-join-token-2"' >/dev/null

echo "All checks passed."
