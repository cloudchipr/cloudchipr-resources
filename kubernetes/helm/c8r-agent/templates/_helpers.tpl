{{/*
Expand the name of the chart.
*/}}
{{- define "..name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "..fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "..chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "..labels" -}}
helm.sh/chart: {{ include "..chart" . }}
{{ include "..selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "..selectorLabels" -}}
app.kubernetes.io/name: {{ include "..name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels for collector
*/}}
{{- define "..collectorSelectorLabels" -}}
app.kubernetes.io/name: {{ include "..name" . }}-collector
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Allow the release namespace to be overridden for multi-namespace deployment in combined charts
*/}}
{{- define "..namespace" -}}
{{- if .Values.namespaceOverride }}
{{- .Values.namespaceOverride }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Allow the release namespace to be overridden for multi-namespace deployment in combined charts
*/}}
{{- define "..serviceAccountName" -}}
{{- if .Values.serviceAccount.name }}
{{- .Values.serviceAccount.name }}
{{- else }}
{{- include "..fullname" . }}
{{- end }}
{{- end }}

{{- define "..createSecret" -}}
{{- if or .Values.config.c8r_cluster_name .Values.config.c8r_cloud_account .Values.config.c8r_api_key .Values.config.c8r_cluster_id -}}
{{- "true" }}
{{- else }}
{{- "false" }}
{{- end }}
{{- end }}


{{/*
=============================================================================
netmon (eBPF network monitoring) helpers
=============================================================================
*/}}

{{/*
netmon.collector.resolve as a string. An unquoted `off` in a values file is
YAML boolean false (and `on` true), so booleans map to off / auto.
*/}}
{{- define "..netmon.collectorResolve" -}}
{{- $v := .Values.netmon.collector.resolve }}
{{- if kindIs "bool" $v }}
{{- ternary "auto" "off" $v }}
{{- else }}
{{- $v | default "auto" | toString }}
{{- end }}
{{- end }}

{{/*
Validate the netmon values. Included from deployment.yaml (always rendered),
so a bad combination fails every install/upgrade/template run.
*/}}
{{- define "..netmon.validate" -}}
{{- if .Values.netmon.enabled }}
{{- if .Values.networkCollection.enabled }}
{{- fail "netmon.enabled and networkCollection.enabled are mutually exclusive: netmon (eBPF) replaces the kubenetmon conntrack collection. Set networkCollection.enabled=false." }}
{{- end }}
{{- $resolve := .Values.netmon.resolveMode | default "snapshot" }}
{{- if not (has $resolve (list "snapshot" "ondemand" "auto")) }}
{{- fail (printf "netmon.resolveMode must be one of snapshot, ondemand, auto (got %q)" $resolve) }}
{{- end }}
{{- $autoPods := .Values.netmon.resolveAutoPods }}
{{- if not (and (or (kindIs "int" $autoPods) (kindIs "int64" $autoPods) (kindIs "float64" $autoPods)) (ge (float64 $autoPods) 1.0) (eq (float64 $autoPods) (floor (float64 $autoPods)))) }}
{{- fail (printf "netmon.resolveAutoPods must be a positive integer (got %v)" $autoPods) }}
{{- end }}
{{- $collectorResolve := include "..netmon.collectorResolve" . }}
{{- if not (has $collectorResolve (list "auto" "off")) }}
{{- fail (printf "netmon.collector.resolve must be one of auto, off (got %q)" $collectorResolve) }}
{{- end }}
{{- $exp := .Values.netmon.collector.enrollTokenExpirationSeconds }}
{{- if not (and (or (kindIs "int" $exp) (kindIs "int64" $exp) (kindIs "float64" $exp)) (ge (float64 $exp) 600.0) (eq (float64 $exp) (floor (float64 $exp)))) }}
{{- fail (printf "netmon.collector.enrollTokenExpirationSeconds must be an integer of at least 600 (got %v)" $exp) }}
{{- end }}
{{- $mode := .Values.netmon.tls.mode }}
{{- if not (has $mode (list "auto" "files" "disabled")) }}
{{- fail (printf "netmon.tls.mode must be one of auto, files, disabled (got %q)" $mode) }}
{{- end }}
{{- if eq $mode "files" }}
{{- if not .Values.netmon.tls.files.agent.secretName }}
{{- fail "netmon.tls.mode=files requires netmon.tls.files.agent.secretName (a Secret with the CA bundle, certificate and key of the agent)" }}
{{- end }}
{{- if and (not .Values.netmon.tls.files.collector.secretName) (not .Values.netmon.tls.files.collector.volume) }}
{{- fail "netmon.tls.mode=files requires netmon.tls.files.collector.secretName or netmon.tls.files.collector.volume (per-node collector certificates, e.g. the cert-manager CSI driver)" }}
{{- end }}
{{- end }}
{{- if not (kindIs "slice" .Values.netmon.tls.extraSANs) }}
{{- fail "netmon.tls.extraSANs must be a list" }}
{{- end }}
{{- if not (kindIs "map" .Values.netmon.cloudRanges.urls) }}
{{- fail "netmon.cloudRanges.urls must be a map of provider to URL (e.g. {aws: https://mirror.example/ip-ranges.json})" }}
{{- end }}
{{- range $provider, $url := .Values.netmon.cloudRanges.urls }}
{{- if or (not $url) (contains "," (toString $url)) (contains "=" $provider) (contains "," $provider) }}
{{- fail (printf "netmon.cloudRanges.urls.%s: URL must be non-empty and neither provider nor URL may contain ',' (provider must not contain '=')" $provider) }}
{{- end }}
{{- end }}
{{- $attach := toString .Values.netmon.collector.attachMode }}
{{- if eq $attach "tc" }}
{{- fail "netmon.collector.attachMode=tc is reserved and not implemented by the collector; use auto (default), cgroup2 or legacy" }}
{{- end }}
{{- if not (has $attach (list "auto" "cgroup2" "legacy")) }}
{{- fail (printf "netmon.collector.attachMode must be one of auto, cgroup2, legacy (got %q)" $attach) }}
{{- end }}
{{- if not (kindIs "bool" .Values.netmon.collector.cgroupV1Support) }}
{{- fail "netmon.collector.cgroupV1Support must be a boolean (true or false)" }}
{{- end }}
{{- if not (kindIs "bool" .Values.netmon.collector.appArmorUnconfined) }}
{{- fail "netmon.collector.appArmorUnconfined must be a boolean (true or false)" }}
{{- end }}
{{- $selType := .Values.netmon.collector.seLinuxType }}
{{- if not (or (kindIs "string" $selType) (kindIs "invalid" $selType)) }}
{{- fail "netmon.collector.seLinuxType must be a string (an SELinux type such as spc_t, or \"\" to leave it unset)" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Collector epoch retention in seconds (C8R_NETMON_RETENTION_SECONDS), rendered
on both the agent and the collectors so they always match.

The agent refuses to start unless
  (C8R_NETMON_MAX_LAG_WINDOWS + 1) * C8R_NETMON_WINDOW_SECONDS + C8R_NETMON_PULL_DELAY
    <= C8R_NETMON_RETENTION_SECONDS
(pkg/netmon/server/config.go validateLag). MAX_LAG_WINDOWS and PULL_DELAY are
not chart values: they are read from the agent env (netmon.agent.addEnv, then
addEnv, which the container lists later so it wins), else the agent defaults
10 and 10s.

netmon.retentionSeconds empty (default): auto =
  max(900, ceil(required) + windowSeconds), one extra window of margin; 900
  keeps 60 s windows exactly as before.
netmon.retentionSeconds set: used as is, but fails here when below required
  (no margin), the same rule the agent applies at startup.

PULL_DELAY is a Go duration (time.ParseDuration): "0" or integer h/m/s/ms
parts such as 10s, 1m, 1m30s, 500ms. Anything else (a bare number, which the
agent itself rejects, decimals, valueFrom) fails in auto mode and asks for
an explicit netmon.retentionSeconds; an explicit value is then rendered
unchecked and the agent validates it at startup. Required is computed in
milliseconds so the check matches the agent exactly.
*/}}
{{- define "..netmon.retentionSeconds" -}}
{{- $n := .Values.netmon }}
{{- $win := $n.windowSeconds }}
{{- if not (and (or (kindIs "int" $win) (kindIs "int64" $win) (kindIs "float64" $win)) (ge (float64 $win) 1.0) (eq (float64 $win) (floor (float64 $win)))) }}
{{- fail (printf "netmon.windowSeconds must be a positive integer (got %v)" $win) }}
{{- end }}
{{- $win = int64 $win }}
{{- $maxLagRaw := "10" }}
{{- $pullRaw := "10s" }}
{{- $maxLagSrc := "default" }}
{{- $pullSrc := "default" }}
{{- $env := concat ($n.agent.addEnv | default list) (.Values.addEnv | default list) }}
{{- range $env }}
{{- if eq (toString .name) "C8R_NETMON_MAX_LAG_WINDOWS" }}
{{- $maxLagRaw = ternary (toString .value) "" (hasKey . "value") }}
{{- $maxLagSrc = "addEnv" }}
{{- end }}
{{- if eq (toString .name) "C8R_NETMON_PULL_DELAY" }}
{{- $pullRaw = ternary (toString .value) "" (hasKey . "value") }}
{{- $pullSrc = "addEnv" }}
{{- end }}
{{- end }}
{{- $ret := $n.retentionSeconds }}
{{- $auto := or (kindIs "invalid" $ret) (eq (toString $ret) "") }}
{{- if not (or $auto (regexMatch "^[0-9]+$" (toString $ret))) }}
{{- fail (printf "netmon.retentionSeconds must be a positive integer, or empty for auto (got %v)" $ret) }}
{{- end }}
{{- $parseErr := "" }}
{{- $maxLag := int64 0 }}
{{- if regexMatch "^[0-9]+$" $maxLagRaw }}
{{- $maxLag = int64 $maxLagRaw }}
{{- else }}
{{- $parseErr = printf "C8R_NETMON_MAX_LAG_WINDOWS %q (%s) is not a positive integer literal" $maxLagRaw $maxLagSrc }}
{{- end }}
{{- $pullMs := int64 0 }}
{{- if ne $pullRaw "0" }}
{{- $parts := regexFindAll "[0-9]+(ms|h|m|s)" $pullRaw -1 }}
{{- if or (not $parts) (ne (join "" $parts) $pullRaw) }}
{{- $parseErr = printf "C8R_NETMON_PULL_DELAY %q (%s) is not a Go duration with integer h/m/s/ms parts such as 10s, 1m or 1m30s (a bare number is rejected by the agent too)" $pullRaw $pullSrc }}
{{- else }}
{{- range $parts }}
{{- if hasSuffix "ms" . }}
{{- $pullMs = add $pullMs (int64 (trimSuffix "ms" .)) }}
{{- else if hasSuffix "h" . }}
{{- $pullMs = add $pullMs (mul (int64 (trimSuffix "h" .)) 3600000) }}
{{- else if hasSuffix "m" . }}
{{- $pullMs = add $pullMs (mul (int64 (trimSuffix "m" .)) 60000) }}
{{- else }}
{{- $pullMs = add $pullMs (mul (int64 (trimSuffix "s" .)) 1000) }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- if $parseErr }}
{{- /* Explicit retention: the chart cannot check it, the agent will at startup. */}}
{{- if $auto }}
{{- fail (printf "cannot compute netmon.retentionSeconds automatically: %s. Fix the value, or set netmon.retentionSeconds explicitly to at least (C8R_NETMON_MAX_LAG_WINDOWS + 1) x netmon.windowSeconds (%d) + pull delay, in seconds" $parseErr $win) }}
{{- end }}
{{- toString $ret }}
{{- else }}
{{- if lt $maxLag 1 }}
{{- fail "C8R_NETMON_MAX_LAG_WINDOWS must be >= 1 (the agent rejects 0)" }}
{{- end }}
{{- $requiredMs := add (mul (add $maxLag 1) $win 1000) $pullMs }}
{{- $requiredS := div (add $requiredMs 999) 1000 }}
{{- $autoS := max 900 (add $requiredS $win) }}
{{- if $auto }}
{{- $autoS }}
{{- else }}
{{- $retS := int64 (toString $ret) }}
{{- if lt (mul $retS 1000) $requiredMs }}
{{- fail (printf "netmon.retentionSeconds=%d is below the minimum the agent accepts: (C8R_NETMON_MAX_LAG_WINDOWS + 1) x windowSeconds + C8R_NETMON_PULL_DELAY = (%d + 1) x %d + %s = %d s (MAX_LAG_WINDOWS from %s, PULL_DELAY from %s). Raise netmon.retentionSeconds to at least %d, or leave it empty for auto (%d)" $retS $maxLag $win $pullRaw $requiredS $maxLagSrc $pullSrc $requiredS $autoS) }}
{{- end }}
{{- $retS }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Capabilities added to the non-privileged collector, as a YAML list:
netmon.collector.capabilities plus, with netmon.collector.cgroupV1Support,
  SYS_PTRACE:      host-netns listener table (ns/net and fd/* links of
                   host processes, a ptrace access check) and the
                   <proc>/1/root dataplane hint;
  DAC_READ_SEARCH: the listener table's fd scan of non-root host processes
                   (<proc>/<pid>/fd is mode 0500, owned by the process uid);
  SYS_ADMIN:       private cgroup2 mount at /run/c8r-netmon/cgroup2 on pure
                   cgroup v1 (legacy) nodes.
Deduplicated, so listing them in capabilities as well is harmless.
*/}}
{{- define "..netmon.collectorCapabilities" -}}
{{- $caps := list }}
{{- range .Values.netmon.collector.capabilities }}
{{- $caps = append $caps (toString .) }}
{{- end }}
{{- if .Values.netmon.collector.cgroupV1Support }}
{{- $caps = concat $caps (list "SYS_PTRACE" "DAC_READ_SEARCH" "SYS_ADMIN") }}
{{- end }}
{{- with ($caps | uniq) }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/* Name prefix of the netmon collector objects. */}}
{{- define "..netmon.collectorName" -}}
{{- printf "%s-netmon-collector" (include "..fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Name of the agent-side netmon RBAC objects. */}}
{{- define "..netmon.agentRBACName" -}}
{{- printf "%s-netmon" (include "..fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "..netmon.collectorServiceAccountName" -}}
{{- default (include "..netmon.collectorName" .) .Values.netmon.collector.serviceAccount.name }}
{{- end }}

{{/*
Collector pod selector labels. app.kubernetes.io/component=netmon-collector
is what the agent discovers collectors by and what enrollment requires
(C8R_NETMON_COLLECTOR_SELECTOR). The name label differs from the agent's
(..selectorLabels), so neither the agent Deployment nor the netmon Service
ever select collector pods.
*/}}
{{- define "..netmon.collectorSelectorLabels" -}}
app.kubernetes.io/name: {{ include "..name" . }}-netmon-collector
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: netmon-collector
{{- end }}

{{/*
Selector the agent uses to discover collectors and to admit enrollments.
Equality-only on purpose: the agent turns it into the label set an enrolling
pod must carry. Scoped to this release so a foreign pod carrying only the
component label cannot enroll.
*/}}
{{- define "..netmon.collectorSelector" -}}
{{- printf "app.kubernetes.io/component=netmon-collector,app.kubernetes.io/instance=%s" .Release.Name }}
{{- end }}

{{/* Agent URL the collectors dial (a DNS SAN of the agent certificate). */}}
{{- define "..netmon.serverURL" -}}
{{- $scheme := ternary "http" "https" (eq .Values.netmon.tls.mode "disabled") }}
{{- printf "%s://%s.%s.svc:%v" $scheme .Values.netmon.service.name (include "..namespace" .) .Values.netmon.agent.serverPort }}
{{- end }}

{{/* Collector image; defaults to the agent image (same binary, C8R_MODE=collector). */}}
{{- define "..netmon.collectorImage" -}}
{{- $img := .Values.netmon.collector.image }}
{{- $registry := default .Values.image.registry $img.registry }}
{{- $repository := default .Values.image.repository $img.repository }}
{{- $tag := default (default .Chart.AppVersion .Values.image.tag) $img.tag }}
{{- if $registry }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- else }}
{{- printf "%s:%s" $repository $tag }}
{{- end }}
{{- end }}

{{/* Is the CA ConfigMap/Secret machinery (auto mode) in use? */}}
{{- define "..netmon.tlsAuto" -}}
{{- if and .Values.netmon.enabled (eq .Values.netmon.tls.mode "auto") }}true{{- end }}
{{- end }}

{{/*
Collector enrollment token (netmon.tls.mode=auto): a projected
serviceAccountToken with this audience, mounted at this directory (file
"token"). Must match pki.EnrollAudience and pki.DefaultEnrollTokenFile in
c8r-agent (pkg/netmon/pki/config.go); the agent's TokenReview requires the
audience, so the token the collector sends is useless against the API server.
*/}}
{{- define "..netmon.enrollAudience" -}}c8r-netmon{{- end }}
{{- define "..netmon.enrollTokenDir" -}}/var/run/secrets/c8r-netmon/enroll{{- end }}

{{/*
TLS env shared by agent and collector. Arg: dict "root" $ "side" ("agent"|"collector").
*/}}
{{- define "..netmon.tlsEnv" -}}
{{- $v := .root.Values.netmon -}}
- name: C8R_NETMON_TLS_MODE
  value: {{ $v.tls.mode | quote }}
{{- if eq $v.tls.mode "auto" }}
- name: C8R_NETMON_CA_NAME
  value: {{ $v.tls.caName | quote }}
{{- if eq .side "agent" }}
# Enrollment accepts only tokens of this service account, from DaemonSet pods.
- name: C8R_NETMON_COLLECTOR_SERVICE_ACCOUNT
  value: {{ include "..netmon.collectorServiceAccountName" .root | quote }}
{{- else }}
# Projected token with audience {{ include "..netmon.enrollAudience" . }} (volume enroll-token).
- name: C8R_NETMON_ENROLL_TOKEN_FILE
  value: {{ printf "%s/token" (include "..netmon.enrollTokenDir" .) | quote }}
{{- end }}
{{- else if eq $v.tls.mode "files" }}
{{- $f := index $v.tls.files .side }}
{{- $dir := $v.tls.files.mountPath }}
- name: C8R_NETMON_TLS_CA_FILE
  value: {{ printf "%s/%s" $dir $f.caKey | quote }}
- name: C8R_NETMON_TLS_CERT_FILE
  value: {{ printf "%s/%s" $dir $f.certKey | quote }}
- name: C8R_NETMON_TLS_KEY_FILE
  value: {{ printf "%s/%s" $dir $f.keyKey | quote }}
{{- end }}
{{- end }}

{{/*
Container the HPA scales on: the kubenetmon server when networkCollection is
on, otherwise the agent itself (netmon). The two modes are mutually exclusive
(..netmon.validate).
*/}}
{{- define "..hpaContainer" -}}
{{- if .Values.networkCollection.enabled }}c8r-network-agent{{- else }}c8r-agent{{- end }}
{{- end }}

{{/*
=============================================================================
Resource presets (resourcesPreset)
=============================================================================
The preset table. Every preset sizes both containers of a cluster size:
  agent:     the c8r-agent container of the Deployment (every replica).
  collector: the netmon collector DaemonSet container (one per node).
The reasoning behind each number is in values.yaml (resourcesPreset) and in
the README "Sizing" section; keep the three in sync.

"default" is the value-file default and NOT a size: it keeps the chart's
historical agent requests (100m / 128Mi, no limit) while netmon is disabled,
so upgrading an existing install renders the same resources, and resolves
to "small" while netmon is enabled (netmon is new in 4.5.0, so no install
depends on the old agent default with netmon on). The collector's
"default" equals "small" (the historical collector default).
No CPU limits anywhere: the leader's window commit bursts to a few cores for
a few seconds per window, and a CPU limit would only throttle it.
*/}}
{{- define "..resourcesPresetTable" -}}
default:
  agent:
    requests:
      cpu: 100m
      memory: 128Mi
      ephemeral-storage: 128Mi
  collector:
    requests:
      cpu: 20m
      memory: 64Mi
    limits:
      memory: 256Mi
small:
  agent:
    requests:
      cpu: 100m
      memory: 256Mi
      ephemeral-storage: 128Mi
    limits:
      memory: 512Mi
  collector:
    requests:
      cpu: 20m
      memory: 64Mi
    limits:
      memory: 256Mi
medium:
  agent:
    requests:
      cpu: 250m
      memory: 1Gi
      ephemeral-storage: 128Mi
    limits:
      memory: 1536Mi
  collector:
    requests:
      cpu: 20m
      memory: 64Mi
    limits:
      memory: 256Mi
large:
  agent:
    requests:
      cpu: 500m
      memory: 2560Mi
      ephemeral-storage: 128Mi
    limits:
      memory: 4Gi
  collector:
    requests:
      cpu: 20m
      memory: 64Mi
    limits:
      memory: 256Mi
xlarge:
  agent:
    requests:
      cpu: "1"
      memory: 4Gi
      ephemeral-storage: 128Mi
    limits:
      memory: 6Gi
  collector:
    requests:
      cpu: 20m
      memory: 64Mi
    limits:
      memory: 384Mi
none:
  agent: {}
  collector: {}
{{- end }}

{{/* resourcesPreset as a string; "" (or null) means "default". */}}
{{- define "..resourcesPresetName" -}}
{{- .Values.resourcesPreset | default "default" | toString }}
{{- end }}

{{/*
Effective resources of one component as YAML. Arg: dict "root" $ "component"
("agent"|"collector"). Precedence, per field: the user's `resources`
(agent) / `netmon.collector.resources` (collector) are deep-merged over the
preset, so every field the user sets wins and every field the user leaves
out comes from the preset. To drop a preset field (e.g. its memory limit)
use resourcesPreset=none and set the full block. This is the same merge Helm
applied to the old built-in defaults, so partial overrides such as
`--set resources.requests.memory=256Mi` keep rendering what they did.
*/}}
{{- define "..resources" -}}
{{- $root := .root }}
{{- $name := include "..resourcesPresetName" $root }}
{{- if and (eq $name "default") (eq .component "agent") $root.Values.netmon.enabled }}
{{- $name = "small" }}
{{- end }}
{{- $table := include "..resourcesPresetTable" $root | fromYaml }}
{{- $preset := index $table $name | default dict }}
{{- $base := index $preset .component | default dict | deepCopy }}
{{- $user := ternary $root.Values.resources $root.Values.netmon.collector.resources (eq .component "agent") | default dict }}
{{- $res := mergeOverwrite $base (deepCopy $user) }}
{{- with $res }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
A memory quantity in bytes, or "" when it is not a plain Kubernetes
quantity this helper understands (number with an optional binary or decimal
suffix, e.g. 512Mi, 2Gi, 1.5Gi, 1G, 1073741824). Used for GOMEMLIMIT and the
request <= limit check; callers fall back gracefully on "".
*/}}
{{- define "..memoryBytes" -}}
{{- $v := . }}
{{- if or (kindIs "float64" $v) (kindIs "int" $v) (kindIs "int64" $v) }}
{{- printf "%d" (int64 $v) }}
{{- else if kindIs "string" $v }}
{{- $m := regexFindAll "^([0-9]+(?:\\.[0-9]+)?)(Ki|Mi|Gi|Ti|k|M|G|T)?$" $v 1 }}
{{- if $m }}
{{- $num := regexReplaceAll "^([0-9]+(?:\\.[0-9]+)?).*$" $v "${1}" | float64 }}
{{- $suffix := regexReplaceAll "^[0-9.]+" $v "" }}
{{- $mult := dict "" 1.0 "k" 1e3 "M" 1e6 "G" 1e9 "T" 1e12 "Ki" 1024.0 "Mi" 1048576.0 "Gi" 1073741824.0 "Ti" 1099511627776.0 }}
{{- printf "%d" (int64 (floor (mulf $num (index $mult $suffix)))) }}
{{- end }}
{{- end }}
{{- end }}

{{/*
GOMEMLIMIT env entry for a container with a memory limit. Arg: dict
"resources" <effective resources map> "env" <user env list>. The Go runtime
does not read the cgroup limit itself (the agent binary does not set a
memory limit either), so without GOMEMLIMIT the GC only reacts to GOGC and
a window peak can run into the OOM killer. 90% of the limit leaves room for
what the Go runtime does not track (non-Go mappings, kernel memory charged
to the container) and for the GC to catch up before the kernel OOM killer
acts. A limit this helper cannot parse falls back to 100% of the limit
through the Downward API. Skipped when the user's env
already sets GOMEMLIMIT.
*/}}
{{- define "..gomemlimitEnv" -}}
{{- $limit := dig "limits" "memory" "" .resources }}
{{- $userSet := false }}
{{- range .env }}
{{- if and (kindIs "map" .) (eq (toString (index . "name")) "GOMEMLIMIT") }}
{{- $userSet = true }}
{{- end }}
{{- end }}
{{- if and $limit (not $userSet) }}
{{- $bytes := include "..memoryBytes" $limit }}
{{- if $bytes }}
- name: GOMEMLIMIT
  # 90% of limits.memory ({{ $limit }}).
  value: {{ printf "%d" (int64 (floor (mulf ($bytes | float64) 0.9))) | quote }}
{{- else }}
- name: GOMEMLIMIT
  valueFrom:
    resourceFieldRef:
      resource: limits.memory
      divisor: "1"
{{- end }}
{{- end }}
{{- end }}

{{/*
Validate resourcesPreset and the effective resources. Included from
deployment.yaml (always rendered).
*/}}
{{- define "..resources.validate" -}}
{{- $name := include "..resourcesPresetName" . }}
{{- $valid := list "default" "small" "medium" "large" "xlarge" "none" }}
{{- if not (has $name $valid) }}
{{- fail (printf "resourcesPreset must be one of %s (got %q)" (join ", " $valid) $name) }}
{{- end }}
{{- if not (or (kindIs "map" .Values.resources) (kindIs "invalid" .Values.resources)) }}
{{- fail "resources must be a map (requests/limits), or {} to use resourcesPreset" }}
{{- end }}
{{- if not (or (kindIs "map" .Values.netmon.collector.resources) (kindIs "invalid" .Values.netmon.collector.resources)) }}
{{- fail "netmon.collector.resources must be a map (requests/limits), or {} to use resourcesPreset" }}
{{- end }}
{{- $components := list (list "agent" "resources") }}
{{- if .Values.netmon.enabled }}
{{- $components = append $components (list "collector" "netmon.collector.resources") }}
{{- end }}
{{- range $components }}
{{- $res := include "..resources" (dict "root" $ "component" (index . 0)) | fromYaml }}
{{- $req := include "..memoryBytes" (dig "requests" "memory" "" $res) }}
{{- $lim := include "..memoryBytes" (dig "limits" "memory" "" $res) }}
{{- if and $req $lim (gt ($req | float64) ($lim | float64)) }}
{{- $reqShow := dig "requests" "memory" "" $res }}
{{- $limShow := dig "limits" "memory" "" $res }}
{{- if not (kindIs "string" $reqShow) }}{{ $reqShow = $req }}{{ end }}
{{- if not (kindIs "string" $limShow) }}{{ $limShow = $lim }}{{ end }}
{{- fail (printf "%s: requests.memory (%s) is above limits.memory (%s) after applying resourcesPreset=%s. Your value is merged over the preset field by field: raise the limit as well, or use resourcesPreset=none and set the full block." (index . 1) $reqShow $limShow (include "..resourcesPresetName" $)) }}
{{- end }}
{{- end }}
{{- end }}
