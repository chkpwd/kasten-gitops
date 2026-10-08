{{/* The cluster role. Fails early if it is missing or wrong. */}}
{{- define "kasten-mc.role" -}}
{{- $role := .Values.global.kastenMc.role | default "" -}}
{{- if not (has $role (list "primary" "secondary")) -}}
{{- fail (printf "Set global.kastenMc.role to \"primary\" or \"secondary\". Current value: %q." $role) -}}
{{- end -}}
{{- $role -}}
{{- end -}}

{{/* Stops a part from running on the wrong role. */}}
{{- define "kasten-mc.requireRole" -}}
{{- if ne (include "kasten-mc.role" (index . 0)) (index . 1) -}}
{{- fail (printf "%s: use this only on the %s cluster." (index . 2) (index . 1)) -}}
{{- end -}}
{{- end -}}

{{- define "kasten-mc.tokenSecretName" -}}
kasten-mc-join-token-{{ .Values.handoff.token.generation }}
{{- end -}}

{{- define "kasten-mc.labels" -}}
app.kubernetes.io/name: kasten-mc
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: kasten-multicluster
kasten-mc/role: {{ include "kasten-mc.role" . }}
{{- end -}}

{{/*
The Kasten dashboard URL of this cluster. The first match wins:
  1. the full URL you give
  2. the k10 Route values: k10.route.host, k10.route.path, k10.route.tls
  3. the k10 Ingress values: k10.ingress.host, k10.ingress.urlPath,
     k10.ingress.tls
  4. the host that OpenShift gave the k10-route Route. This needs cluster
     access, so it works in Flux and helm install, but not in helm template.
The path follows the k10 chart: the Route or Ingress path, or k10.
Usage: include "kasten-mc.dashboardURL" (list . <url> "<value name>")
*/}}
{{- define "kasten-mc.dashboardURL" -}}
{{- $ctx := index . 0 -}}
{{- $url := index . 1 | default "" -}}
{{- $what := index . 2 -}}
{{- $route := $ctx.Values.k10.route | default dict -}}
{{- $ingress := $ctx.Values.k10.ingress | default dict -}}
{{- if $url -}}
{{- else if and $route.enabled $route.host -}}
{{- $url = printf "%s://%s/%s" (ternary "https" "http" (dig "tls" "enabled" false $route)) $route.host ($route.path | default "k10" | trimAll "/") -}}
{{- else if and $ingress.create $ingress.host -}}
{{- $url = printf "%s://%s/%s" (ternary "https" "http" (dig "tls" "enabled" false $ingress)) $ingress.host ($ingress.urlPath | default "k10" | trimAll "/") -}}
{{- else -}}
{{- $live := lookup "route.openshift.io/v1" "Route" $ctx.Release.Namespace "k10-route" -}}
{{- if and $live $live.spec.host -}}
{{- $url = printf "%s://%s/%s" (ternary "https" "http" (not (empty $live.spec.tls))) $live.spec.host ($live.spec.path | default "k10" | trimAll "/") -}}
{{- end -}}
{{- end -}}
{{- if not $url -}}
{{- fail (printf "Cannot find the Kasten dashboard URL. Set %s, k10.route.host or k10.ingress.host. On OpenShift, install Kasten first so that the k10-route Route exists." $what) -}}
{{- end -}}
{{- if not (regexMatch "^https?://[^/]+/.+" $url) -}}
{{- fail (printf "%s must be a full URL, for example https://<host>/k10. Current value: %q." $what $url) -}}
{{- end -}}
{{- $url -}}
{{- end -}}
