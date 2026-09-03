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
  {{- $_ = set $app "runAsNonRoot" (eq (toString (default $defaults.runAsUser .runAsUser)) "0" | not) -}}
  {{- $_ = set $app "capacity" (default $defaults.capacity .capacity) -}}
  {{- $_ = set $app "cacheCapacity" (default $defaults.cacheCapacity .cacheCapacity) -}}
  {{- $_ = set $app "schedule" (default $defaults.schedule .schedule) -}}
  {{- $_ = set $app "namespace" (default $defaults.namespace .namespace) -}}
  {{- $_ = set $app "createPVC" .createPVC -}}
  {{- $_ = set $app "supplementalGroups" (default list .supplementalGroups) -}}
  {{- /* Per-app opt-in verification (default off; see values.yaml comment).
        Using `or` (not `default`) because sprig's `default` treats an
        explicit `false` as "empty" and would silently flip it back to a
        truthy default — `or` only needs "true wins if set anywhere",
        which is all this ever needs since the baseline default is false. */ -}}
  {{- $_ = set $app "verifyEnabled" (or .verifyEnabled $defaults.verifyEnabled false) -}}
  {{- /* Verification rides the app's own backup schedule by default, so it never adds an extra NFS mount/unmount cycle */ -}}
  {{- $_ = set $app "verifySchedule" (default $app.schedule .verifySchedule) -}}
  {{- $apps = append $apps $app -}}
{{- end -}}
{{- toJson $apps -}}
{{- end -}}
