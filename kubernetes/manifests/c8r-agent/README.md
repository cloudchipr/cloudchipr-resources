# Cloudchipr SaaS Platform Kubernetes Agent

## Installation

- Create Api key in [Cloudchipr UI](https://app.cloudchipr.com/settings/api-keys)

- Create namespace for cloudchipr agent

  ```bash
  kubectl create namespace cloudchipr
  ```

- Create secret with cloudchipr api key:

  ```bash
  kubectl -n cloudchipr create secret generic c8r-agent --from-literal C8R_API_KEY=<REPLACE_WITH_API_KEY>
  ```

- Apply manifests:

  ```bash
  kubectl -n cloudchipr apply -f https://raw.githubusercontent.com/cloudchipr/cloudchipr-resources/refs/heads/main/kubernetes/manifests/c8r-agent/resources.yaml
  ```
