# Kasten multi-cluster with Flux, OpenShift and AWS Secrets Manager

This folder installs Veeam Kasten on two OpenShift clusters with Flux. One
cluster becomes the multi-cluster **primary**. The other joins as a
**secondary**. The join token moves through AWS Secrets Manager.

```mermaid
flowchart LR
  subgraph P["Primary"]
    P1["kasten"] --> P2["handoff: Bootstrap, token, PushSecret"]
  end
  P2 -- "writer IAM user" --> SM[("AWS Secrets Manager")]
  subgraph S["Secondary"]
    S1["kasten"] --> S2["pull: ExternalSecret into mc-join"]
    S2 --> S3["join: mc-join-config"]
  end
  SM -- "reader IAM user" --> S2
  S3 -. "joins over HTTPS" .-> P1
```

## Files

```text
bootstrap/<cluster>/     FluxInstance example: points Flux at clusters/<cluster>
clusters/primary/        Flux stages for the primary: kasten, handoff
clusters/secondary/      Flux stages for the secondary: kasten, pull, join
values/                  Values for each cluster, OpenShift and AWS
charts/kasten-mc/        The chart (Kasten is a subchart). Works with any GitOps engine.
charts/eso-provider-aws/ The ESO ClusterSecretStore for AWS Secrets Manager
docs/                    Architecture, runbook, AWS setup, provider contract, ROSA
```

## Before you start

- Flux Operator, and the `FluxInstance` from `bootstrap/<cluster>/`.
- External Secrets Operator 2.12 on both clusters.
- The AWS resources in [docs/aws.md](docs/aws.md).
- The secondary can reach the primary's Kasten Route over HTTPS.
- If an ingress certificate is private or self-signed: the CA bundle step in
  the [runbook](docs/runbook.md).
- If the secondary already runs Kasten: see "Secondary that already runs
  Kasten" in the [runbook](docs/runbook.md). You do not reinstall it.

Git holds no hostnames. The chart finds each dashboard URL from the k10
Route or Ingress values, or from the live OpenShift Route.

More: [architecture](docs/architecture.md), [runbook](docs/runbook.md),
[AWS setup](docs/aws.md), [provider contract](docs/provider-contract.md),
[ROSA](docs/rosa.md).
