{{- define "boutique-environment.namespace" -}}
{{- default (printf "boutique-%s" .Values.name) .Values.namespace -}}
{{- end -}}

{{- define "boutique-environment.host" -}}
{{- default (printf "boutique-%s.localtest.me" .Values.name) .Values.ingressHost -}}
{{- end -}}

{{/* Repliche dal tier: unica tabella di policy del chart. */}}
{{- define "boutique-environment.replicas" -}}
{{- if eq .Values.tier "critical" -}}2{{- else -}}1{{- end -}}
{{- end -}}

{{- define "boutique-environment.labels" -}}
app.kubernetes.io/name: online-boutique
app.kubernetes.io/instance: {{ .Values.name }}
app.kubernetes.io/managed-by: krateo
boutique.example/owner: {{ .Values.owner | quote }}
boutique.example/tier: {{ .Values.tier | quote }}
{{- end -}}
