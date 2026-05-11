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
| `autoscaling.enabled`                                              | Enable HorizontalPodAutoscaler for the deployment. Requires `networkCollection.enabled=true`. When enabled, `replicas` is ignored.                   | `false`                |
| `autoscaling.minReplicas`                                          | Minimum number of replicas.                                                                                                                          | `1`                    |
| `autoscaling.maxReplicas`                                          | Maximum number of replicas.                                                                                                                          | `10`                   |
| `autoscaling.targetCPUUtilizationPercentage`                       | Target average CPU utilization of the `c8r-network-agent` container (as a percentage of its request). Set to `null` to disable the CPU metric.       | `80`                   |
| `autoscaling.targetMemoryUtilizationPercentage`                    | Target average memory utilization of the `c8r-network-agent` container (as a percentage of its request). Set to `null` to disable the memory metric. | `80`                   |
| `autoscaling.behavior`                                             | HPA scaling behavior (scaleUp/scaleDown policies). Passed through as-is.                                                                             | `{}`                   |
| `autoscaling.annotations`                                          | Annotations for the HorizontalPodAutoscaler.                                                                                                         | `{}`                   |
| `autoscaling.labels`                                               | Extra labels for the HorizontalPodAutoscaler.                                                                                                        | `{}`                   |
