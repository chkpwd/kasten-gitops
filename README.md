# GitOps Kasten Instances

Examples of how to manage Veeam Kasten with GitOps in mind.

> **Disclaimer:** These layouts are examples only. They show one way to run
> Kasten with GitOps, not the only way, and they are not supported
> products. Read every file before you use it. Change what does not suit
> your environment, for example cluster names, namespaces, versions, the
> secret backend, credentials and security settings. Test your changes on
> a non-production cluster first.

## Layouts

| Path | GitOps engine | Platform | Secret backend | Status |
|---|---|---|---|---|
| [`argocd/MCM`](argocd/MCM) | Argo CD | AKS | Azure Key Vault | |
| [`flux/MCM`](flux/MCM) | Flux | OpenShift | AWS Secrets Manager | |
