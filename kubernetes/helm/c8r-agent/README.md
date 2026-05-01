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

## Testing

Template-level unit tests live in `tests/` and run with the [helm-unittest](https://github.com/helm-unittest/helm-unittest) plugin (no cluster required):

```bash
helm plugin install https://github.com/helm-unittest/helm-unittest
helm unittest .
```

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
| `nodeSelector`                                                     | Node Selector labels for pod assignment.                                                                                                             | `{}`                   |
| `affinity`                                                         | Affinity settings for pod assignment.                                                                                                                | `{}`                   |
| `tolerations`                                                      | Tolerations for pod assignment (Optional).                                                                                                           | `[]`                   |
| `resources.requests.cpu`                                           | CPU request for the container.                                                                                                                       | `100m`                 |
| `resources.requests.memory`                                        | Memory request for the container.                                                                                                                    | `128Mi`                |
| `resources.requests.ephemeral-storage`                             | Ephemeral storage request for the container.                                                                                                         | `128Mi`                |
| `securityContext.allowPrivilegeEscalation`                         | Allow privilege escalation for the container.                                                                                                        | `false`                |
| `securityContext.readOnlyRootFilesystem`                           | Read only root filesystem for the container.                                                                                                         | `false`                |
| `securityContext.runAsNonRoot`                                     | Run as non root user for the container.                                                                                                              | `true`                 |
| `securityContext.runAsUser`                                        | Run as 10001 user for the container.                                                                                                                 | `10001`                |
| `securityContext.capabilities.drop`                                | Drop all capabilities for the container.                                                                                                             | `["ALL"]`              |
| `podSecurityContext`                                               | Security context for the pod.                                                                                                                        | `{}`                   |
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
| `networkCollection.collector.nodeSelector`                         | Node Selector labels for collector pod assignment.                                                                                                   | `{}`                   |
| `networkCollection.collector.resources.requests.cpu`               | cpu request for network agent container                                                                                                              | `50m`                  |
| `networkCollection.collector.resources.requests.memory`            | memory request for network agent container                                                                                                           | `64Mi`                 |
| `networkCollection.collector.resources.requests.ephemeral-storage` | node ephemeral storage request request for network agent container                                                                                   | `64Mi`                 |
| `networkCollection.collector.addEnvFrom`                           | Add envFrom to the network agent container.                                                                                                          | `[]`                   |
| `networkCollection.collector.addEnv`                               | Add env to the network agent container.                                                                                                              | `[]`                   |
| `autoscaling.hpa.enabled`                                          | Enable HorizontalPodAutoscaler for the deployment. Requires `networkCollection.enabled=true`. When enabled, `replicas` is ignored.                   | `false`                |
| `autoscaling.hpa.minReplicas`                                      | Minimum number of replicas.                                                                                                                          | `1`                    |
| `autoscaling.hpa.maxReplicas`                                      | Maximum number of replicas.                                                                                                                          | `10`                   |
| `autoscaling.hpa.targetCPUUtilizationPercentage`                   | Target average CPU utilization of the `c8r-network-agent` container (as a percentage of its request). Set to `null` to disable the CPU metric.       | `80`                   |
| `autoscaling.hpa.targetMemoryUtilizationPercentage`                | Target average memory utilization of the `c8r-network-agent` container (as a percentage of its request). Set to `null` to disable the memory metric. | `80`                   |
| `autoscaling.hpa.behavior`                                         | HPA scaling behavior (scaleUp/scaleDown policies). Passed through as-is.                                                                             | `{}`                   |
| `autoscaling.hpa.annotations`                                      | Annotations for the HorizontalPodAutoscaler.                                                                                                         | `{}`                   |
| `autoscaling.hpa.labels`                                           | Extra labels for the HorizontalPodAutoscaler.                                                                                                        | `{}`                   |
| `autoscaling.vpa.deployment.enabled`                               | Enable VerticalPodAutoscaler for the deployment. Requires the VPA controller (autoscaling.k8s.io) to be installed in the cluster.                    | `false`                |
| `autoscaling.vpa.deployment.updateMode`                            | VPA update mode: `Off`, `Initial`, `Recreate`, or `Auto`. With HPA on, must be `Off` unless `networkAgent.mode` is `Off`.                            | `Off`                  |
| `autoscaling.vpa.deployment.minReplicas`                           | Minimum replicas required before VPA will evict pods. `null` uses the controller default.                                                            | `null`                 |
| `autoscaling.vpa.deployment.annotations`                           | Annotations for the deployment VerticalPodAutoscaler.                                                                                                | `{}`                   |
| `autoscaling.vpa.deployment.labels`                                | Extra labels for the deployment VerticalPodAutoscaler.                                                                                               | `{}`                   |
| `autoscaling.vpa.deployment.agent.mode`                            | Per-container update mode for `c8r-agent`. Empty inherits `updateMode`. Set to `Off` to opt this container out of updates.                           | `""`                   |
| `autoscaling.vpa.deployment.agent.minAllowed`                      | Minimum allowed resources for `c8r-agent` (e.g. `{cpu: 100m, memory: 128Mi}`).                                                                       | `{}`                   |
| `autoscaling.vpa.deployment.agent.maxAllowed`                      | Maximum allowed resources for `c8r-agent`.                                                                                                           | `{}`                   |
| `autoscaling.vpa.deployment.agent.controlledResources`             | Resources VPA will manage on `c8r-agent`. Empty defers to the controller default (`["cpu","memory"]`).                                               | `[]`                   |
| `autoscaling.vpa.deployment.agent.controlledValues`                | What VPA controls on `c8r-agent`: `RequestsAndLimits` or `RequestsOnly`. Empty defers to the controller default.                                     | `""`                   |
| `autoscaling.vpa.deployment.networkAgent.mode`                     | Per-container update mode for `c8r-network-agent`. Set to `Off` when HPA is on so HPA can scale on this container without VPA fighting it.           | `""`                   |
| `autoscaling.vpa.deployment.networkAgent.minAllowed`               | Minimum allowed resources for `c8r-network-agent`.                                                                                                   | `{}`                   |
| `autoscaling.vpa.deployment.networkAgent.maxAllowed`               | Maximum allowed resources for `c8r-network-agent`.                                                                                                   | `{}`                   |
| `autoscaling.vpa.deployment.networkAgent.controlledResources`      | Resources VPA will manage on `c8r-network-agent`.                                                                                                    | `[]`                   |
| `autoscaling.vpa.deployment.networkAgent.controlledValues`         | What VPA controls on `c8r-network-agent`.                                                                                                            | `""`                   |
| `autoscaling.vpa.collector.enabled`                                | Enable VerticalPodAutoscaler for the network collector DaemonSet. Requires `networkCollection.enabled=true`.                                         | `false`                |
| `autoscaling.vpa.collector.updateMode`                             | VPA update mode for the collector: `Off`, `Initial`, `Recreate`, or `Auto`.                                                                          | `Off`                  |
| `autoscaling.vpa.collector.minReplicas`                            | Minimum replicas required before VPA will evict collector pods. `null` uses the controller default.                                                  | `null`                 |
| `autoscaling.vpa.collector.annotations`                            | Annotations for the collector VerticalPodAutoscaler.                                                                                                 | `{}`                   |
| `autoscaling.vpa.collector.labels`                                 | Extra labels for the collector VerticalPodAutoscaler.                                                                                                | `{}`                   |
| `autoscaling.vpa.collector.mode`                                   | Per-container update mode for the `collector` container.                                                                                             | `""`                   |
| `autoscaling.vpa.collector.minAllowed`                             | Minimum allowed resources for the `collector` container.                                                                                             | `{}`                   |
| `autoscaling.vpa.collector.maxAllowed`                             | Maximum allowed resources for the `collector` container.                                                                                             | `{}`                   |
| `autoscaling.vpa.collector.controlledResources`                    | Resources VPA will manage on the `collector` container.                                                                                              | `[]`                   |
| `autoscaling.vpa.collector.controlledValues`                       | What VPA controls on the `collector` container.                                                                                                      | `""`                   |

## Upgrading from 3.x to 4.x

Chart 4.0.0 reorganises autoscaling values under a single `autoscaling` key. Update your overrides as follows:

| 3.x key                          | 4.x key                                |
| -------------------------------- | -------------------------------------- |
| `autoscaling.enabled`            | `autoscaling.hpa.enabled`              |
| `autoscaling.minReplicas`        | `autoscaling.hpa.minReplicas`          |
| `autoscaling.maxReplicas`        | `autoscaling.hpa.maxReplicas`          |
| `autoscaling.target*`            | `autoscaling.hpa.target*`              |
| `autoscaling.behavior`           | `autoscaling.hpa.behavior`             |
| `autoscaling.annotations/labels` | `autoscaling.hpa.annotations/labels`   |
