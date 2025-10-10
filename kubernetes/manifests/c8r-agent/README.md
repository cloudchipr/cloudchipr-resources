# Cloudchipr SaaS Platform Kubernetes Agent

## Installation

- Create Api key in [Cloudchipr Platform](https://app.cloudchipr.com/settings/api-keys)

- Create namespace for cloudchipr agent

  ```bash
  kubectl create namespace cloudchipr
  ```

- Create secret with cloudchipr api key:

  ```bash
  kubectl create secret generic c8r-agent \
    --namespace cloudchipr \
    --from-literal "C8R_API_KEY=<REPLACE_WITH_API_KEY>" \
    --from-literal "C8R_CLUSTER_ID=<REPLACE_WITH_RANDOM_UUID>" \
    --from-literal "C8R_CLOUD_ACCOUNT=<REPLACE_WITH_CLOUD_ACCOUNT>" \
    --from-literal "C8R_CLUSTER_NAME=<REPLACE_WITH_CLUSTER_NAME>"
  ```

- Apply manifests:

  ```bash
  kubectl apply -f https://raw.githubusercontent.com/cloudchipr/cloudchipr-resources/refs/heads/main/kubernetes/manifests/c8r-agent/resources.yaml
  ```
