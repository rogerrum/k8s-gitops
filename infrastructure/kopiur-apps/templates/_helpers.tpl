{{- /*
Helper function to parse apps with defaults from values.yaml
*/ -}}
{{- define "kopiur.parseApps" -}}
{{- $defaults := .Values.defaults -}}
{{- $apps := list -}}
{{- range .Values.apps -}}
  {{- $app := dict "app" .app -}}
  {{- $_ := set $app "pvcSuffix" (default $defaults.pvcSuffix .pvcSuffix) -}}
  {{- $_ = set $app "runAsUser" (default $defaults.runAsUser .runAsUser) -}}
  {{- $_ = set $app "capacity" (default $defaults.capacity .capacity) -}}
  {{- $_ = set $app "cacheCapacity" (default $defaults.cacheCapacity .cacheCapacity) -}}
  {{- $_ = set $app "schedule" (default $defaults.schedule .schedule) -}}
  {{- $_ = set $app "namespace" (default $defaults.namespace .namespace) -}}
  {{- $_ = set $app "createPVC" .createPVC -}}
  {{- $_ = set $app "ignoreFileErrors" (default false .ignoreFileErrors) -}}
  {{- $_ = set $app "supplementalGroups" (default list .supplementalGroups) -}}
  {{- $apps = append $apps $app -}}
{{- end -}}
{{- toJson $apps -}}
{{- end -}}
