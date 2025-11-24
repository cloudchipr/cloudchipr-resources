# Cloudchipr SaaS Platform Kubernetes Agent

## This is a Beta feature and has not been officially released yet

This chart deploys Cloudchipr kubernetes agent to your local cluster

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

If chart is alraedy added to repo list, run:

```bash
helm repo update cloudchipr
```

## How to install

Run the following command to install the chart

```bash
helm upgrade -i c8r-agent -n cloudchipr --create-namespace cloudchipr/c8r-agent \
  --set "config.c8r_api_key=<REPLACE_WITH_API_KEY>" \
  --set "config.c8r_cluster_id=<REPLACE_WITH_RANDOM_UUID>" \
  --set "config.c8r_cluster_name=<REPLACE_WITH_CLUSTER_NAME>" \
  --set "config.c8r_cloud_account=<REPLACE_WITH_CLOUD_ACCOUNT>"
```

To uninstall the chart:

```bash
helm uninstall c8r-agent -n c8r-agent
kubectl delete namespace cloudchipr
```

## Parameters

### General Configuration

| Name                                       | Description                                                                                                                     | Value                  |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------- | ---------------------- |
| `nameOverride`                             | Overrides the default name where the chart will be installed (Optional).                                                        | `""`                   |
| `namespaceOverride`                        | Overrides the default namespace where the chart will be installed (Optional).                                                   | `""`                   |
| `replicas`                                 | Number of replicas for the deployment.                                                                                          | `1`                    |
| `image.registry`                           | Registry to use for the image.                                                                                                  | `quay.io`              |
| `image.repository`                         | Image repository to use for the image.                                                                                          | `cloudchipr/c8r-agent` |
| `image.tag`                                | Image tag to use for the image. Default is `.Chart.AppVersion`.                                                                 | `""`                   |
| `image.pullPolicy`                         | Image pull policy to use for the image. Default is `Always`.                                                                    | `Always`               |
| `serviceAccount.name`                      | service account name to create                                                                                                  | `c8r-agent`            |
| `serviceAccount.labels`                    | service account labels                                                                                                          | `{}`                   |
| `serviceAccount.annotations`               | service account annotations                                                                                                     | `{}`                   |
| `config.c8r_api_key`                       | Token to authenticate with Cloudchipr API. Required if `existingSecret` is not provided.                                        | `""`                   |
| `config.c8r_cluster_id`                    | Cluster ID to identify the cluster in Cloudchipr. Required if `existingSecret` is not provided.                                 | `""`                   |
| `config.c8r_cluster_name`                  | Cluster name to identify the cluster in Cloudchipr. Required if `existingSecret` is not provided.                               | `""`                   |
| `config.c8r_cloud_account`                 | Cloud account name, e.g. AWS account id, GCP project id, Azure subscriptoin name. Required if `existingSecret` is not provided. | `""`                   |
| `config.existingSecret`                    | Existing secret to use for the API key, it must have all keys from `config`                                                     | `""`                   |
| `labels`                                   | Extra labels for the deployment.                                                                                                | `{}`                   |
| `annotations`                              | Annotations for the deployment.                                                                                                 | `{}`                   |
| `podLabels`                                | Extra labels for the pod.                                                                                                       | `{}`                   |
| `podAnnotations`                           | Annotations for the pod.                                                                                                        | `{}`                   |
| `nodeSelector`                             | Node Selector labels for pod assignment.                                                                                        | `{}`                   |
| `affinity`                                 | Affinity settings for pod assignment.                                                                                           | `{}`                   |
| `tolerations`                              | Tolerations for pod assignment (Optional).                                                                                      | `[]`                   |
| `resources.requests.cpu`                   | CPU request for the container.                                                                                                  | `100m`                 |
| `resources.requests.memory`                | Memory request for the container.                                                                                               | `128Mi`                |
| `resources.requests.ephemeral-storage`     | Ephemeral storage request for the container.                                                                                    | `128Mi`                |
| `securityContext.allowPrivilegeEscalation` | Allow privilege escalation for the container.                                                                                   | `false`                |
| `securityContext.readOnlyRootFilesystem`   | Read only root filesystem for the container.                                                                                    | `false`                |
| `securityContext.runAsNonRoot`             | Run as non root user for the container.                                                                                         | `true`                 |
| `securityContext.runAsUser`                | Run as 10001 user for the container.                                                                                            | `10001`                |
| `securityContext.capabilities.drop`        | Drop all capabilities for the container.                                                                                        | `["ALL"]`              |
| `podSecurityContext`                       | Security context for the pod.                                                                                                   | `{}`                   |
| `addEnvFrom`                               | Add envFrom to the container.                                                                                                   | `[]`                   |
| `addEnv`                                   | Add env to the container.                                                                                                       | `[]`                   |
