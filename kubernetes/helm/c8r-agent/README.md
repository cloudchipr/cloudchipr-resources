# Cloudchipr SaaS Platform Kubernetes Agent

## This is a Beta feature and has not been officially released yet

This chart deploys Cloudchipr Kubernetes Agent to your local cluster

## Requirements

* Kubernetes >= [1.19](https://kubernetes.io/releases/)
* Helm >= [3](https://github.com/helm/helm/releases)

## Installation

[Helm](https://helm.sh) must be installed to use the charts.  Please refer to
Helm's [documentation](https://helm.sh/docs) to get started.

Once Helm has been set up correctly, add the repo as follows:

```bash
helm repo add cloudchipr https://helm-charts.cloudchipr.io
helm repo update cloudchipr
```

If chart is already added to repo list, run:

```bash
helm repo update cloudchipr
```

## How to install

Run the following command to install the chart with network collection enabled:

```bash
helm upgrade --install c8r-agent -n cloudchipr --create-namespace cloudchipr/c8r-agent \
  --set-string "config.c8r_api_key=<REPLACE_WITH_API_KEY>" \
  --set-string "config.c8r_cluster_id=<REPLACE_WITH_RANDOM_UUID>" \
  --set-string "config.c8r_cluster_name=<REPLACE_WITH_CLUSTER_NAME>" \
  --set-string "config.c8r_cloud_account=<REPLACE_WITH_CLOUD_ACCOUNT>" \
  --set networkCollection.enabled="true"
```

Run the following command to install the chart without network collection enabled:

```bash
helm upgrade --install c8r-agent -n cloudchipr --create-namespace cloudchipr/c8r-agent \
  --set-string "config.c8r_api_key=<REPLACE_WITH_API_KEY>" \
  --set-string "config.c8r_cluster_id=<REPLACE_WITH_RANDOM_UUID>" \
  --set-string "config.c8r_cluster_name=<REPLACE_WITH_CLUSTER_NAME>" \
  --set-string "config.c8r_cloud_account=<REPLACE_WITH_CLOUD_ACCOUNT>"
```

To uninstall the chart:

```bash
helm uninstall c8r-agent -n c8r-agent
kubectl delete namespace cloudchipr
```

## Network monitoring (netmon, eBPF)

`netmon.enabled=true` deploys the eBPF network monitoring of c8r-agent. It replaces
`networkCollection` (kubenetmon, conntrack); the two are mutually exclusive and the
chart fails if both are enabled.

What gets rendered:

* a collector DaemonSet `<fullname>-netmon-collector` (same image, `C8R_MODE=collector`,
  `hostNetwork`, host `/proc` read-only) with its own ServiceAccount and RBAC,
* the Service `netmon.service.name` (default `c8r-agent-netmon`, port 9410) in front of
  all agent replicas,
* netmon env, ports and probes on the agent container, and the agent RBAC additions.

Every agent replica serves collector metadata and enrollment behind the netmon Service;
only the leader pulls from the collectors. `autoscaling.enabled=true` is therefore
allowed with netmon (the HPA scales on the `c8r-agent` container). Extra replicas spread
the metadata/enrollment load but do not reduce the leader's memory, so with netmon consider
`autoscaling.targetMemoryUtilizationPercentage=null` and size the leader instead (see Sizing).

```bash
helm upgrade --install c8r-agent -n cloudchipr --create-namespace cloudchipr/c8r-agent \
  --set-string "config.c8r_api_key=<REPLACE_WITH_API_KEY>" \
  --set-string "config.c8r_cluster_id=<REPLACE_WITH_RANDOM_UUID>" \
  --set-string "config.c8r_cluster_name=<REPLACE_WITH_CLUSTER_NAME>" \
  --set-string "config.c8r_cloud_account=<REPLACE_WITH_CLOUD_ACCOUNT>" \
  --set netmon.enabled=true
```

Requirements and notes:

* Linux kernel >= 5.8 on every node. The collector probes its features at start; on a
  node it cannot monitor it stays up but not ready (`/healthz` 503) and
  `c8r_netmon_collector_mode_info{reason}` says why. No crash loop.
* The collector runs as uid 0 with `capabilities.drop: [ALL]` plus `BPF`, `PERFMON`,
  `NET_ADMIN` and `SYS_RESOURCE`, a read-only root filesystem and no privilege
  escalation, AppArmor-unconfined and with the SELinux type `spc_t` (both below).
  Verified on kind and on k3s with Ubuntu 20.04 (AppArmor), Amazon Linux 2 and Rocky 8
  (SELinux enforcing). `netmon.collector.privileged=true` is the fallback for node images
  where that is still not enough, e.g. a seccomp or other LSM policy blocking `bpf()`.
* Linux security modules. Both settings only apply to the collector container (not the
  agent) and are no-ops on nodes without that LSM:
  * **AppArmor** (`netmon.collector.appArmorUnconfined=true`): the runtime's default
    profile (`cri-containerd.apparmor.d`, Ubuntu nodes including AKS and Ubuntu EKS)
    denies writes under `/sys/fs/bpf` and ptrace reads of host processes. Without
    `Unconfined`, map pinning silently fails on every such node (cgroup v2 included:
    counters not yet pulled are lost on a collector restart) and the host listener table
    is denied even with `cgroupV1Support`, so traffic of hostNetwork servers that predate
    the collector stays unresolved (and each attempt is a kernel audit record). Rendered
    as `securityContext.appArmorProfile: {type: Unconfined}` on Kubernetes >= 1.30 and as
    the pod annotation `container.apparmor.security.beta.kubernetes.io/collector:
    unconfined` before (`helm template` needs `--kube-version` to pick the right one).
    With `false`, a profile can be set through `netmon.collector.podAnnotations` on
    clusters older than 1.30.
  * **SELinux** (`netmon.collector.seLinuxType=spc_t`): with container labelling
    (RHEL/Rocky with container-selinux, k3s `selinux: true`, OpenShift) the default
    `container_t` cannot read the host `/proc`, mount cgroup2 or create BPF maps, so the
    collector stays not ready (`reason="mount_cgroup2"` on cgroup v1 nodes) even with
    `cgroupV1Support`. `spc_t` (as Cilium uses) lifts that. `""` leaves it unset.
  * Pod Security Admission: the collector already needs the `privileged` level
    (hostNetwork, hostPath, added capabilities), which also allows these two.
  * **OpenShift**: the chart creates no SecurityContextConstraints. Bind the collector
    ServiceAccount to an SCC that allows hostNetwork, hostPath volumes, uid 0, the added
    capabilities and a custom SELinux type (`seLinuxContext: RunAsAny`), e.g. the built-in
    `privileged` SCC.
* The host's `/proc` is mounted read-only at `/host/proc` (`C8R_NETMON_HOST_PROC`), so
  the collector sees the host pid namespace without `hostPID`. It reads the cgroup
  layout from it and, on cgroup v1 nodes, socket owners and host listeners.
  `netmon.collector.hostPID` is kept but not needed. An `emptyDir` is mounted at
  `/run/c8r-netmon` (the root filesystem is read-only).
* cgroup layout (`netmon.collector.attachMode=auto` detects it per node):
  * **cgroup v2 (unified)**: the default. Attribution by cgroup id, no extra privileges.
  * **hybrid** (v1 controllers plus a cgroup2 `unified` mount): owner attribution works
    with the defaults. Attributing pre-existing hostNetwork servers through the host
    listener table needs `netmon.collector.cgroupV1Support=true` (`SYS_PTRACE` and
    `DAC_READ_SEARCH`); without them that table misses those servers
    (`c8r_netmon_identity_listener_scan_denied`).
  * **pure cgroup v1 (legacy)**, e.g. EKS Amazon Linux 2: set
    `netmon.collector.cgroupV1Support=true` (adds `SYS_PTRACE`, `DAC_READ_SEARCH` and
    `SYS_ADMIN`, the latter for a private cgroup2 mount at `/run/c8r-netmon/cgroup2`).
    Without it the collector
    stays up but not ready, with `reason="mount_cgroup2"` in
    `c8r_netmon_collector_mode_info`.

  `SYS_PTRACE` also enables the dataplane hint from `<proc>/1/root`; without it the
  dataplane is inferred from the CNI pods on the node. With `privileged=true`,
  `cgroupV1Support` is moot.
* Map pinning (`netmon.collector.pinPath`, on by default) keeps undrained counters across
  collector restarts and needs bpffs mounted at `/sys/fs/bpf` on the node (the default on
  EKS, GKE and AKS images). If the path is not on bpffs the collector logs a warning and
  runs unpinned; set it to `""` to disable pinning explicitly.
* Cloud IP ranges: the agent downloads the public cloud providers' IP ranges and serves
  them to the collectors (`netmon.cloudRanges.*`). Air-gapped clusters should set
  `netmon.cloudRanges.enabled=false` or point `netmon.cloudRanges.urls` at a mirror, e.g.
  `--set netmon.cloudRanges.urls.aws=https://mirror.internal/aws/ip-ranges.json`.
* Sizing: the leader's netmon pipeline memory grows with flow cardinality (the number
  of distinct flows per window), not just with node count. The default agent
  `resources` fit small clusters; for large or very chatty clusters set a higher memory
  request/limit on the agent and watch the leader's memory before tightening it.
* Collectors bind ports 9408 and 9409 on the node IP, so only one netmon release per
  cluster. Allow agent pods to reach node IPs on 9409, and nodes to reach the agent
  Service on 9410, if NetworkPolicies or security groups restrict that.
* Ports: collector 9408 (plain `/livez`, `/healthz`, `/metrics`), 9409 (mTLS API);
  agent 9410 (TLS API + enrollment), 9411 (optional UI), 9412 (plain `/livez`,
  `/healthz`, `/metrics`). Both probes use the plain ports.
* `auto` TLS mode: the agent creates the Secret and ConfigMap `netmon.tls.caName`
  (default `c8r-agent-netmon-ca`). They are not managed by Helm and intentionally survive
  `helm uninstall`, so a reinstall keeps the same CA and existing trust. To reset the CA
  (or clean up completely), delete them after uninstalling:
  `kubectl -n <ns> delete secret,configmap <netmon.tls.caName>` (default `c8r-agent-netmon-ca`).
* `files` TLS mode: `netmon.tls.files.agent.secretName` holds the agent CA bundle,
  certificate and key. Each collector needs a certificate with CN
  `c8r-netmon-collector:<node>` and an IP SAN for its node IP, so either a shared
  `netmon.tls.files.collector.secretName` whose certificate lists every node IP, or a
  per-pod `netmon.tls.files.collector.volume` (for example a CSI driver).
* UI: `netmon.ui.enabled=true`, then
  `kubectl -n <ns> port-forward <leader pod> 9411:9411` (the leader is the holder of the
  Lease `c8r-agent`) and log in with `kubectl -n <ns> create token <agent service account>`.

RBAC granted when `netmon.enabled=true`:

| Subject | Scope | Rule | Why |
| ------- | ----- | ---- | --- |
| collector | ClusterRole | `pods`, `nodes`: get/list/watch | Map local cgroups to pods on its node, read its node's provider id/zone (informers use field selectors, which RBAC cannot express) |
| collector | Role (auto mode) | `configmaps` `[caName]`: get/list/watch | Trust the CA bundle (list/watch are authorized by name through the `metadata.name` field selector) |
| agent | ClusterRole (auto mode or UI) | `tokenreviews`: create | Authenticate collector enrollment tokens and UI tokens |
| agent | ClusterRole (UI) | `selfsubjectreviews`: create | Find its own identity for the UI allowlist |
| agent | Role (auto mode) | `secrets`, `configmaps` `[caName]`: get/update | Load, rotate and publish the CA |
| agent | Role (auto mode) | `secrets`, `configmaps`: create | Create the CA objects on first start (RBAC cannot restrict create by name) |

Pod/node/service reads and leases for the agent are already in the base ClusterRole/Role.

### Pod disruption budget

With `replicas` > 1 or `autoscaling.enabled=true` the chart renders a PodDisruptionBudget
`<fullname>` with `maxUnavailable: 1` for the agent Deployment (with or without netmon).
Disable it with `podDisruptionBudget.enabled=false`.

### Network monitoring parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `netmon.enabled` | Enable eBPF network monitoring (collector DaemonSet + agent netmon server). Mutually exclusive with `networkCollection.enabled`. | `false` |
| `netmon.windowSeconds` | Window length in seconds (`C8R_NETMON_WINDOW_SECONDS`), set on both agent and collectors so they always match. | `60` |
| `netmon.retentionSeconds` | Collector epoch retention in seconds (`C8R_NETMON_RETENTION_SECONDS`), set on both sides. Must be at least one window. | `900` |
| `netmon.resolveMode` | How collectors learn remote pod/node/Service identities (`C8R_NETMON_RESOLVE_MODE`): `snapshot` (every collector polls the full cluster snapshot), `ondemand` (collectors get a slim snapshot and ask the agent `/v1/resolve` for the in-cluster IPs they actually talk to; for large clusters) or `auto` (the leader switches to `ondemand` above `resolveAutoPods` pod IPs and back below 75% of it). Collectors that predate on-demand resolution keep getting the full snapshot. | `snapshot` |
| `netmon.resolveAutoPods` | Pod IP count above which `resolveMode=auto` switches to on-demand resolution (`C8R_NETMON_RESOLVE_AUTO_PODS`, a positive integer). | `20000` |
| `netmon.service.name` | Name of the agent Service the collectors dial (`C8R_NETMON_SERVICE_NAME`). Its DNS names are in the agent certificate. | `c8r-agent-netmon` |
| `netmon.service.annotations` | Annotations for the netmon Service. | `{}` |
| `netmon.agent.serverPort` | Agent netmon API port (`C8R_NETMON_SERVER_PORT`): `/v1/metadata`, `/v1/cloudranges`, `/v1/resolve`, `/v1/resolve/changes`, `/v1/certs/sign`. TLS unless `netmon.tls.mode=disabled`. | `9410` |
| `netmon.agent.plainPort` | Agent plain HTTP port (`C8R_NETMON_PLAIN_PORT`): `/livez`, `/healthz`, `/metrics`. Used by the probes. | `9412` |
| `netmon.agent.addEnv` | Extra env for the agent container, only when netmon is enabled (e.g. `C8R_NETMON_PULL_DELAY`, `C8R_NETMON_SHARD`). | `[]` |
| `netmon.cloudRanges.enabled` | Fetch the public cloud provider IP ranges on the agent, served to the collectors on `/v1/cloudranges` (`C8R_NETMON_CLOUD_RANGES_ENABLED`). Air-gapped clusters: set to false or point `urls` at a mirror. | `true` |
| `netmon.cloudRanges.timeout` | Timeout of one cloud ranges download (`C8R_NETMON_CLOUD_RANGES_TIMEOUT`). | `60s` |
| `netmon.cloudRanges.urls` | Per-provider URL overrides (`C8R_NETMON_CLOUD_RANGES_URLS`, rendered as sorted `provider=url` pairs), e.g. `{aws: https://mirror.internal/ip-ranges.json}`. Empty: built-in upstream URLs. | `{}` |
| `netmon.tls.mode` | Transport security: `auto` (agent-owned CA, collectors enroll), `files` (bring your own certificates, e.g. cert-manager) or `disabled` (plain HTTP, development only). | `auto` |
| `netmon.tls.caName` | Name of the CA Secret and ConfigMap the agent creates and updates in `auto` mode (`C8R_NETMON_CA_NAME`). Not managed by Helm and kept on uninstall. | `c8r-agent-netmon-ca` |
| `netmon.tls.extraSANs` | Extra DNS names and IPs for the agent certificate (`C8R_NETMON_TLS_EXTRA_SANS`), `auto` mode. | `[]` |
| `netmon.tls.files.mountPath` | Directory the `files` mode Secrets are mounted at, in both agent and collector. | `/etc/c8r-netmon/tls` |
| `netmon.tls.files.agent.secretName` | Secret with the agent CA bundle, certificate and key (`files` mode). Certificate: CN `c8r-netmon-agent:<pod>`, serverAuth+clientAuth, DNS SANs of `netmon.service.name`. | `""` |
| `netmon.tls.files.agent.caKey` | Key of the CA bundle in the agent Secret. | `ca.crt` |
| `netmon.tls.files.agent.certKey` | Key of the certificate in the agent Secret. | `tls.crt` |
| `netmon.tls.files.agent.keyKey` | Key of the private key in the agent Secret. | `tls.key` |
| `netmon.tls.files.collector.secretName` | Secret with the collector CA bundle, certificate and key (`files` mode). Shared by every collector, so its certificate needs an IP SAN for every node IP; prefer `volume`. | `""` |
| `netmon.tls.files.collector.volume` | Volume source used instead of `secretName` (e.g. `csi` with the cert-manager CSI driver to get a per-node certificate: CN `c8r-netmon-collector:<node>`, IP SAN = node IP). | `{}` |
| `netmon.tls.files.collector.caKey` | File name of the CA bundle in the collector volume. | `ca.crt` |
| `netmon.tls.files.collector.certKey` | File name of the certificate in the collector volume. | `tls.crt` |
| `netmon.tls.files.collector.keyKey` | File name of the private key in the collector volume. | `tls.key` |
| `netmon.ui.enabled` | Serve the netmon web UI on the leader (`C8R_NETMON_UI`). HTTPS unless TLS is disabled; reach it with `kubectl port-forward` to the leader pod. | `false` |
| `netmon.ui.port` | UI port (`C8R_NETMON_UI_PORT`). | `9411` |
| `netmon.ui.windows` | Number of recent windows the UI keeps (`C8R_NETMON_UI_WINDOWS`, max 240). | `30` |
| `netmon.ui.allowedSubjects` | Extra subjects allowed to log in (`C8R_NETMON_UI_ALLOWED_SUBJECTS`): usernames such as `system:serviceaccount:<ns>:<name>`, or `group:<name>`. The agent's own service account is always allowed. | `[]` |
| `netmon.ui.insecure` | Serve the UI API WITHOUT authentication (`C8R_NETMON_UI_INSECURE`). Local development only. | `false` |
| `netmon.collector.image.registry` | Collector image registry. Empty: `image.registry`. | `""` |
| `netmon.collector.image.repository` | Collector image repository. Empty: `image.repository`. | `""` |
| `netmon.collector.image.tag` | Collector image tag. Empty: `image.tag`, then `.Chart.AppVersion`. Collector and agent share the netmon API, keep them on the same version. | `""` |
| `netmon.collector.image.pullPolicy` | Collector image pull policy. Empty: `image.pullPolicy`. | `""` |
| `netmon.collector.port` | Collector API port on the node IP (`C8R_NETMON_PORT`, mTLS, agent certificates only). Also set on the agent (`C8R_NETMON_COLLECTOR_PORT`). | `9409` |
| `netmon.collector.plainPort` | Collector plain HTTP port on the node IP (`C8R_NETMON_PLAIN_PORT`): `/livez`, `/healthz` (503 until enrolled), `/metrics`. | `9408` |
| `netmon.collector.drainInterval` | How often the BPF flow map is drained (`C8R_NETMON_DRAIN_INTERVAL`, min 100ms). | `5s` |
| `netmon.collector.pinPath` | bpffs directory for map pinning (`C8R_NETMON_PIN_PATH`), keeps undrained counters across collector restarts. Needs bpffs mounted at /sys/fs/bpf on the node (default on EKS, GKE, AKS); without it the collector logs a warning and runs unpinned. "" disables pinning. | `/sys/fs/bpf/c8r-netmon` |
| `netmon.collector.conntrack` | Resolve ClusterIP traffic to backends through netlink conntrack (`C8R_NETMON_CONNTRACK`). | `true` |
| `netmon.collector.resolve` | On-demand identity resolution on the collector (`C8R_NETMON_RESOLVE`): `auto` (use it whenever the agent offers it, see `netmon.resolveMode`) or `off` (kill switch: always ask for the full snapshot). | `auto` |
| `netmon.collector.logLevel` | Collector log level. | `info` |
| `netmon.collector.hostPID` | Share the host PID namespace. Not needed: the host's `/proc` is always mounted read-only at `/host/proc` (`C8R_NETMON_HOST_PROC`), which works with or without it. | `false` |
| `netmon.collector.cgroupV1Support` | Add `SYS_PTRACE` and `DAC_READ_SEARCH` (host listener table for pre-existing hostNetwork servers, `<proc>/1/root` dataplane hint) and `SYS_ADMIN` (private cgroup2 mount on pure cgroup v1 nodes, e.g. EKS Amazon Linux 2) to the collector. Not needed on cgroup v2 nodes; moot with `privileged`. | `false` |
| `netmon.collector.attachMode` | Attach mode (`C8R_NETMON_ATTACH_MODE`, rendered only when not `auto`): `auto` detects the node's cgroup layout, `cgroup2` forces the unified behaviour (fails on non-cgroup2 nodes), `legacy` forces owner attribution (testing). `tc` is reserved and rejected. | `auto` |
| `netmon.collector.privileged` | Run the collector privileged instead of with `netmon.collector.capabilities`. Escape hatch for node images where the capability set plus `appArmorUnconfined`/`seLinuxType` is still not enough (e.g. a seccomp or other LSM policy blocking `bpf()`). | `false` |
| `netmon.collector.appArmorUnconfined` | Run the collector container AppArmor-unconfined (`appArmorProfile: {type: Unconfined}` on Kubernetes >= 1.30, the `container.apparmor.security.beta.kubernetes.io/collector` pod annotation before). The runtime default profile denies map pinning under /sys/fs/bpf and the host listener table. No effect on nodes without AppArmor. | `true` |
| `netmon.collector.seLinuxType` | SELinux type of the collector container (`seLinuxOptions.type`). `container_t` cannot read the host /proc, mount cgroup2 or create BPF maps. Ignored on nodes without SELinux. `""` leaves it unset. | `spc_t` |
| `netmon.collector.capabilities` | Linux capabilities added to the collector (all others are dropped). BPF+PERFMON: load programs/maps and ring buffer (kernel >= 5.8); NET_ADMIN: attach cgroup_skb programs and read conntrack via netlink; SYS_RESOURCE: raise RLIMIT_MEMLOCK on kernels < 5.11. | `["BPF","PERFMON","NET_ADMIN","SYS_RESOURCE"]` |
| `netmon.collector.resources.requests.cpu` | Collector CPU request (spike: ~0.5% of a core). | `20m` |
| `netmon.collector.resources.requests.memory` | Collector memory request (spike: ~15MB RSS). | `64Mi` |
| `netmon.collector.resources.limits.memory` | Collector memory limit. Also exported as GOMEMLIMIT. Raise for nodes with very many flows (`C8R_NETMON_MAX_RING_ROWS`). | `256Mi` |
| `netmon.collector.priorityClassName` | PriorityClass of the collector pods (e.g. `system-node-critical`). Falls back to top-level `priorityClassName`. | `""` |
| `netmon.collector.tolerations` | Collector tolerations. Default tolerates every taint so it runs on all nodes. | `[{"operator":"Exists"}]` |
| `netmon.collector.nodeSelector` | Collector node selector. | `{}` |
| `netmon.collector.updateStrategy` | DaemonSet update strategy. | `{"type":"RollingUpdate","rollingUpdate":{"maxUnavailable":"10%"}}` |
| `netmon.collector.terminationGracePeriodSeconds` | Grace period; the collector detaches its programs on SIGTERM. | `30` |
| `netmon.collector.podLabels` | Extra labels for the collector pods. | `{}` |
| `netmon.collector.podAnnotations` | Annotations for the collector pods. | `{}` |
| `netmon.collector.serviceAccount.name` | Collector ServiceAccount name. Empty: `<fullname>-netmon-collector`. | `""` |
| `netmon.collector.serviceAccount.annotations` | Collector ServiceAccount annotations. | `{}` |
| `netmon.collector.addEnv` | Extra env for the collector (e.g. `C8R_NETMON_MAX_FLOWS`, `C8R_NETMON_INTERNET_IP_CAP`). | `[]` |
| `netmon.collector.addEnvFrom` | Extra envFrom for the collector. | `[]` |
| `netmon.collector.extraVolumes` | Extra volumes for the collector pods. | `[]` |
| `netmon.collector.extraVolumeMounts` | Extra volume mounts for the collector container. | `[]` |

## Parameters

### General Configuration

| Name                                                               | Description                                                                                                                                          | Value                  |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------- |
| `nameOverride`                                                     | Overrides the default name where the chart will be installed (Optional).                                                                             | `""`                   |
| `namespaceOverride`                                                | Overrides the default namespace where the chart will be installed (Optional).                                                                        | `""`                   |
| `replicas`                                                         | Number of replicas for the deployment.                                                                                                               | `1`                    |
| `image.registry`                                                   | Registry to use for the image.                                                                                                                       | `quay.io`              |
| `image.repository`                                                 | Image repository to use for the image.                                                                                                               | `cloudchipr/c8r-agent` |
| `image.tag`                                                        | Image tag to use for the image. Default is `.Chart.AppVersion`.                                                                                      | `""`                   |
| `image.pullPolicy`                                                 | Image pull policy to use for the image. Default is `Always`.                                                                                         | `Always`               |
| `serviceAccount.name`                                              | service account name to create                                                                                                                       | `c8r-agent`            |
| `serviceAccount.labels`                                            | service account labels                                                                                                                               | `{}`                   |
| `serviceAccount.annotations`                                       | service account annotations                                                                                                                          | `{}`                   |
| `config.c8r_api_key`                                               | Token to authenticate with Cloudchipr API. Can be set in existing secret as C8R_API_KEY.                                                             | `""`                   |
| `config.c8r_cluster_id`                                            | Cluster ID to identify the cluster in Cloudchipr. Can be set in existing secret as C8R_CLUSTER_ID.                                                   | `""`                   |
| `config.c8r_cluster_name`                                          | Cluster name to identify the cluster in Cloudchipr. Can be set in existing secret as C8R_CLUSTER_NAME.                                               | `""`                   |
| `config.c8r_cloud_account`                                         | Cloud account identifier, e.g. AWS account id, GCP project id, Azure subscription name. Can be set in existing secret as C8R_CLOUD_ACCOUNT.          | `""`                   |
| `config.existingSecret`                                            | Existing secret to use for the API key, it must have all keys from `config`.                                                                         | `""`                   |
| `labels`                                                           | Extra labels for the deployment.                                                                                                                     | `{}`                   |
| `annotations`                                                      | Annotations for the deployment.                                                                                                                      | `{}`                   |
| `podLabels`                                                        | Extra labels for the pod.                                                                                                                            | `{}`                   |
| `podAnnotations`                                                   | Annotations for the pod.                                                                                                                             | `{}`                   |
| `nodeSelector`                                                     | Node Selector labels for pod assignment. Applies only to agent, not collector DaemonSet.                                                             | `{}`                   |
| `affinity`                                                         | Affinity settings for pod assignment. Applies only to agent, not collector DaemonSet.                                                                | `{}`                   |
| `tolerations`                                                      | Tolerations for pod assignment. Applies only to agent, not collector DaemonSet.                                                                      | `[]`                   |
| `resources.requests.cpu`                                           | CPU request for the container.                                                                                                                       | `100m`                 |
| `resources.requests.memory`                                        | Memory request for the container.                                                                                                                    | `128Mi`                |
| `resources.requests.ephemeral-storage`                             | Ephemeral storage request for the container.                                                                                                         | `128Mi`                |
| `securityContext.allowPrivilegeEscalation`                         | Allow privilege escalation for the container.                                                                                                        | `false`                |
| `securityContext.readOnlyRootFilesystem`                           | Read only root filesystem for the container.                                                                                                         | `false`                |
| `securityContext.runAsNonRoot`                                     | Run as non root user for the container.                                                                                                              | `true`                 |
| `securityContext.runAsUser`                                        | Run as 10001 user for the container.                                                                                                                 | `10001`                |
| `securityContext.capabilities.drop`                                | Drop all capabilities for the container.                                                                                                             | `["ALL"]`              |
| `podSecurityContext`                                               | Security context for the pod.                                                                                                                        | `{}`                   |
| `priorityClassName`                                                | Name of an existing PriorityClass to assign to pods. The chart does not create the PriorityClass.                                                    | `""`                   |
| `addEnvFrom`                                                       | Add envFrom to the container.                                                                                                                        | `[]`                   |
| `addEnv`                                                           | Add env to the container.                                                                                                                            | `[]`                   |
| `networkCollection.enabled`                                        | enable network agent to collect networking data                                                                                                      | `false`                |
| `networkCollection.server.enableMetrics`                           | enable metrics port and add prometheus scrape annotations to service                                                                                 | `false`                |
| `networkCollection.server.resources.requests.cpu`                  | cpu request for network agent container                                                                                                              | `100m`                 |
| `networkCollection.server.resources.requests.memory`               | memory request for network agent container                                                                                                           | `512Mi`                |
| `networkCollection.server.resources.requests.ephemeral-storage`    | node ephemeral storage request request for network agent container                                                                                   | `64Mi`                 |
| `networkCollection.server.addEnvFrom`                              | Add envFrom to the network agent container.                                                                                                          | `[]`                   |
| `networkCollection.server.addEnv`                                  | Add env to the network agent container.                                                                                                              | `[]`                   |
| `networkCollection.collector.collectionInterval`                   | interval for collecting network data                                                                                                                 | `5s`                   |
| `networkCollection.collector.skipConntrackSanityCheck`             | skip conntrack sanity check                                                                                                                          | `false`                |
| `networkCollection.collector.uptimeWaitDuration`                   | duration to wait for uptime before collecting                                                                                                        | `300s`                 |
| `networkCollection.collector.priorityClassName`                    | PriorityClass for the collector DaemonSet pods. Falls back to top-level `priorityClassName` when empty.                                              | `""`                   |
| `networkCollection.collector.nodeSelector`                         | Node Selector labels for collector pod assignment.                                                                                                   | `{}`                   |
| `networkCollection.collector.resources.requests.cpu`               | cpu request for network agent container                                                                                                              | `50m`                  |
| `networkCollection.collector.resources.requests.memory`            | memory request for network agent container                                                                                                           | `64Mi`                 |
| `networkCollection.collector.resources.requests.ephemeral-storage` | node ephemeral storage request request for network agent container                                                                                   | `64Mi`                 |
| `networkCollection.collector.addEnvFrom`                           | Add envFrom to the network agent container.                                                                                                          | `[]`                   |
| `networkCollection.collector.addEnv`                               | Add env to the network agent container.                                                                                                              | `[]`                   |
| `gpuCollection.nvidia`                                             | Nvidia DCGM Exporter service url, format: http[s]://<service_name>[.namespace[.svc.cluster.local]]:port                                              | `""`                   |
| `autoscaling.enabled`                                              | Enable HorizontalPodAutoscaler for the deployment. Requires `networkCollection.enabled=true` or `netmon.enabled=true`. When enabled, `replicas` is ignored. | `false`                |
| `autoscaling.minReplicas`                                          | Minimum number of replicas.                                                                                                                          | `1`                    |
| `autoscaling.maxReplicas`                                          | Maximum number of replicas.                                                                                                                          | `10`                   |
| `autoscaling.targetCPUUtilizationPercentage`                       | Target average CPU utilization of the `c8r-network-agent` container (`c8r-agent` with netmon) (as a percentage of its request). Set to `null` to disable the CPU metric.       | `80`                   |
| `autoscaling.targetMemoryUtilizationPercentage`                    | Target average memory utilization of the `c8r-network-agent` container (`c8r-agent` with netmon) (as a percentage of its request). Set to `null` to disable the memory metric. | `80`                   |
| `autoscaling.behavior`                                             | HPA scaling behavior (scaleUp/scaleDown policies). Passed through as-is.                                                                             | `{}`                   |
| `autoscaling.annotations`                                          | Annotations for the HorizontalPodAutoscaler.                                                                                                         | `{}`                   |
| `autoscaling.labels`                                               | Extra labels for the HorizontalPodAutoscaler.                                                                                                        | `{}`                   |
| `podDisruptionBudget.enabled`                                      | Create a PodDisruptionBudget (`maxUnavailable: 1`) for the agent Deployment when `replicas` > 1 or `autoscaling.enabled`. | `true` |
| `podDisruptionBudget.labels`                                       | Extra labels for the PodDisruptionBudget. | `{}` |
| `podDisruptionBudget.annotations`                                  | Annotations for the PodDisruptionBudget. | `{}` |
