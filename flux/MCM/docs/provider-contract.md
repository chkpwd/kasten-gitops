# Provider contract

The chart and a secret backend meet at Kubernetes objects only. To add a
backend, you replace the store. Everything else stays the same.

## The objects

| Object | Name and namespace | Content | Owner |
|---|---|---|---|
| Token request (primary) | Secret `kasten-mc-join-token-<generation>`, `kasten-io-mc`, type `dist.kio.kasten.io/join-token` | Key `token`. Kasten writes it. | Helm owns the object. Kasten owns the data. |
| Writer store (primary) | ClusterSecretStore `kasten-mc-writer`, usable only from `kasten-io-mc` | Backend login with write access | Provider |
| Remote secret | `handoff.remoteKey` (default `kasten-mc-join-token`) in the backend | The token as text | ESO creates it |
| Reader store (secondary) | ClusterSecretStore `kasten-mc-reader`, usable only from `kasten-io` | Backend login with read access | Provider |
| Token (secondary) | Secret `mc-join`, `kasten-io` | Key `token` | ESO |
| Join trigger (secondary) | ConfigMap `mc-join-config`, `kasten-io` | `cluster-name`, `cluster-ingress` | Chart |

Kasten sets these names: the Secret type, `kasten-io-mc`, `mc-join`,
`mc-join-config` and the `token` key (Kasten docs, Multi-Cluster Getting
Started).

## AWS (this repository)

- Store: `charts/eso-provider-aws`, ESO `aws` provider, `SecretsManager`,
  IAM user access keys. Region and secret name: `values/aws.yaml`.
- AWS setup: [aws.md](aws.md).
- Writer IAM actions: `DescribeSecret`, `GetSecretValue`, `PutSecretValue`,
  `DeleteResourcePolicy`, plus `CreateSecret` and `TagResource` with the tag
  `managed-by=external-secrets`. ESO calls `DeleteResourcePolicy` on every
  update, even with no resource policy.
- Reader IAM action: `GetSecretValue`.
- ESO creates the AWS secret on the first push. If you create it yourself,
  add the tag `managed-by=external-secrets`. ESO does not write to a secret
  without this tag.

## How to add a backend

> Only AWS is in the Flux tree. Azure Key Vault is in `argocd/MCM`
> (Argo CD, AKS).

1. Check your ESO version supports push and pull for the backend.
2. Add `charts/eso-provider-<name>` with one ClusterSecretStore. Name it
   `kasten-mc-writer` on the primary and `kasten-mc-reader` on the
   secondary. Limit each to its namespace.
3. Add it to `charts/kasten-mc/Chart.yaml` with
   `condition: eso-provider-<name>.enabled`.
4. Add `values/<name>.yaml` for any `handoff.push.metadata` the
   backend needs.
5. In the push and pull stages, use that values file and turn the provider on.
6. Document the setup and teardown steps. Never print or save the
   credentials. Give the primary write access and the secondary read access
   only.
7. Test the push, the pull, the join and a token rotation before you call
   it supported.

## ESO support by backend

Source: <https://external-secrets.io/latest/introduction/stability-support/>

| Backend | Pull | Push |
|---|---|---|
| AWS Secrets Manager | yes | yes |
| Azure Key Vault | yes | yes |
| HashiCorp Vault | yes | yes |
| Google Secret Manager | yes | yes |
| Akeyless | yes | yes |
| CyberArk Conjur | yes | unclear: check your version |
| IBM Cloud Secrets Manager, Doppler, OpenBao, Delinea | yes | no |

A backend with no push needs another way to receive the token.
