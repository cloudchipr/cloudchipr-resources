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
Render a single VPA containerPolicies entry from a (containerName, cfg) pair,
or render nothing when cfg has no overrides. cfg is expected to expose:
  mode, minAllowed, maxAllowed, controlledResources, controlledValues.
Usage: include "..vpaContainerPolicy" (list "c8r-agent" .Values.autoscaling.vpa.deployment.agent)
*/}}
{{- define "..vpaContainerPolicy" -}}
{{- $name := index . 0 -}}
{{- $cfg := index . 1 | default dict -}}
{{- if or $cfg.mode (gt (len ($cfg.minAllowed | default dict)) 0) (gt (len ($cfg.maxAllowed | default dict)) 0) (gt (len ($cfg.controlledResources | default list)) 0) $cfg.controlledValues }}
- containerName: {{ $name }}
  {{- with $cfg.mode }}
  mode: {{ . | quote }}
  {{- end }}
  {{- with $cfg.minAllowed }}
  minAllowed:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $cfg.maxAllowed }}
  maxAllowed:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $cfg.controlledResources }}
  controlledResources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $cfg.controlledValues }}
  controlledValues: {{ . | quote }}
  {{- end }}
{{- end -}}
{{- end -}}

