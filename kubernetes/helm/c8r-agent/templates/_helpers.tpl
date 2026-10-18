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
Validate the netmon values. Included from deployment.yaml (always rendered),
so a bad combination fails every install/upgrade/template run.
*/}}
{{- define "..netmon.validate" -}}
{{- if .Values.netmon.enabled }}
{{- if .Values.networkCollection.enabled }}
{{- fail "netmon.enabled and networkCollection.enabled are mutually exclusive: netmon (eBPF) replaces the kubenetmon conntrack collection. Set networkCollection.enabled=false." }}
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
{{- if not (kindIs "slice" .Values.netmon.ui.allowedSubjects) }}
{{- fail "netmon.ui.allowedSubjects must be a list" }}
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
TLS env shared by agent and collector. Arg: dict "root" $ "side" ("agent"|"collector").
*/}}
{{- define "..netmon.tlsEnv" -}}
{{- $v := .root.Values.netmon -}}
- name: C8R_NETMON_TLS_MODE
  value: {{ $v.tls.mode | quote }}
{{- if eq $v.tls.mode "auto" }}
- name: C8R_NETMON_CA_NAME
  value: {{ $v.tls.caName | quote }}
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
