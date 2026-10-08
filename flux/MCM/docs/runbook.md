# Runbook

> Each cluster command names its context.

## 1. Prerequisites (each cluster, one time)

1. Install the Flux Operator (for example from OperatorHub). Then apply
   the `FluxInstance` example for the cluster:
   [`../bootstrap/ocp-primary/fluxinstance.yaml`](../bootstrap/ocp-primary/fluxinstance.yaml)
   or [`../bootstrap/ocp-secondary/fluxinstance.yaml`](../bootstrap/ocp-secondary/fluxinstance.yaml).
   With `multitenant: false`, helm-controller and kustomize-controller get
   cluster-admin rights, so OpenShift runs them with the `anyuid` SCC.
2. If ESO is not installed, install it from its Helm chart. On OpenShift,
   set `adaptSecurityContext=force`:

   ```bash
   helm install external-secrets external-secrets --repo https://charts.external-secrets.io --version 2.12.0 --namespace external-secrets --create-namespace --set global.compatibility.openshift.adaptSecurityContext=force --kube-context <CTX> --wait
   ```
3. Make sure the secondary can reach the primary's Kasten Route over HTTPS.
4. If a cluster's ingress certificate comes from a private or self-signed
   CA, do the steps in "Private or self-signed ingress certificates" below
   before you install Kasten.
5. If the secondary already runs Kasten, see "Secondary that already runs
   Kasten" below.

## Private or self-signed ingress certificates

The secondary connects to the primary's Kasten Route over HTTPS. The primary
also opens the secondary's dashboard through `cluster-ingress`. If an
ingress certificate is not signed by a well-known CA, each cluster must
trust the other's root CA. This includes the OpenShift default ingress
certificate, which is self-signed, and certificates from your own CA.

Kasten trusts extra CA certificates from a ConfigMap (Helm value
`cacertconfigmap.name`, default key `custom-ca-bundle.pem`). Put the CA
certificates of both clusters into one file and create the same ConfigMap
on both.

1. On each cluster, get its root CAs. Use the commands from Kasten's
   "Manual Root CA Certificates Extraction"
   (<https://docs.kasten.io/latest/access/authentication/>). Write the
   output to `primary.pem` and `secondary.pem`.

   - **No cluster-wide proxy** (Method 1). The ingress CA and the API server
     certificates. The second command also adds the API server's own
     certificate. This does no harm.

     ```bash
     oc --context <CTX> get secret router-ca -n openshift-ingress-operator -o jsonpath='{.data.tls\.crt}' | base64 --decode > <cluster>.pem
     ```

     ```bash
     oc --context <CTX> get secret external-loadbalancer-serving-certkey -n openshift-kube-apiserver -o jsonpath='{.data.tls\.crt}' | base64 --decode >> <cluster>.pem
     ```

     If a third party signed the API server certificate, use the second
     command from the Kasten page instead.

   - **Cluster-wide proxy** (Method 2). This bundle usually holds your own
     root CA, if you replaced the default ingress certificate:

     ```bash
     oc --context <CTX> get configmap $(oc --context <CTX> get proxy cluster -o jsonpath='{.spec.trustedCA.name}') -n openshift-config -o jsonpath='{.data.ca-bundle\.crt}' > <cluster>.pem
     ```

   The commands read only the `tls.crt` key. Never copy the whole
   `router-ca` Secret: it also holds the CA private key.

2. Join the files: `cat primary.pem secondary.pem > custom-ca-bundle.pem`

3. On each cluster, create the namespace if it does not exist, and the
   ConfigMap:

   ```bash
   oc --context <CTX> create namespace kasten-io
   ```

   ```bash
   oc --context <CTX> -n kasten-io create configmap kasten-mc-ca-bundle --from-file=custom-ca-bundle.pem
   ```

4. Turn it on in `flux/MCM/values/ocp-primary.yaml` and `ocp-secondary.yaml`:

   ```yaml
   k10:
     cacertconfigmap:
       name: kasten-mc-ca-bundle
   ```

If Kasten is already installed and our chart does not manage it, see
"Secondary that already runs Kasten" below.

Create the ConfigMap before Kasten starts. Kasten pods mount it, so a
missing ConfigMap stops them. When a CA changes, create the bundle again
and restart the Kasten pods. The OpenShift default ingress CA is valid for
2 years, and OpenShift does not renew it for you.

## Secondary that already runs Kasten

You can join a cluster that already runs Kasten. You do not reinstall it.
Our chart then adds only the `pull` and `join` stages.

Check these first (read-only):

- Kasten is in the `kasten-io` namespace. The reader store allows only this
  namespace.
- The Route `k10-route` exists in `kasten-io`. If it does not, set
  `handoff.join.clusterIngress` to the dashboard URL.
- The cluster is not in another multi-cluster setup: no `kasten-io-mc`
  namespace, no `mc-join` Secret and no `mc-join-config` ConfigMap.
- The Kasten version can join the primary's version. See Kasten's
  multi-cluster upgrade notes
  (<https://docs.kasten.io/latest/multicluster/upgrading/>).

To make the existing Kasten trust the primary's CA, add `cacertconfigmap`
to its Helm release. Keep its chart version. Use its current values in a
file, not `--reuse-values`, which can drop new chart defaults:

```bash
helm --kube-context <SECONDARY_CONTEXT> -n kasten-io get values k10 -o yaml > k10-values.yaml
```

```bash
helm --kube-context <SECONDARY_CONTEXT> -n kasten-io upgrade k10 k10 --repo https://charts.kasten.io/ --version <current version> -f k10-values.yaml --set cacertconfigmap.name=kasten-mc-ca-bundle --wait
```

Keep `k10-values.yaml`. You need it to remove the setting later. The
upgrade restarts the Kasten pods.

With Flux: remove `kasten.yaml` from
[`../clusters/ocp-secondary/kustomization.yaml`](../clusters/ocp-secondary/kustomization.yaml)
and remove `dependsOn` from
[`../clusters/ocp-secondary/pull/helmrelease.yaml`](../clusters/ocp-secondary/pull/helmrelease.yaml).
Otherwise the `pull` stage waits for a Kasten release that does not exist.

## 2. AWS

Create the IAM users, policies and access keys in your account and region.
Follow [aws.md](aws.md). Set `eso-provider-aws.region` and `handoff.remoteKey`
in [`../values/aws.yaml`](../values/aws.yaml) to match.

## 3. Deploy

You apply nothing by hand. Flux runs the stages in order. Either cluster can
start first.

## 4. Check (read-only)

| Check | Command | Expected |
|---|---|---|
| Stages | `flux --context <CTX> get all -n flux-system` | All Ready. The secondary's `kasten-mc-pull` waits for the token. |
| Token pushed | `oc --context <PRIMARY_CONTEXT> -n kasten-io-mc get pushsecret kasten-mc-join-token` | Ready |
| Token pulled | `oc --context <SECONDARY_CONTEXT> -n kasten-io get externalsecret kasten-mc-join` | Ready |
| Join | `oc --context <SECONDARY_CONTEXT> -n kasten-io get secret mc-join-status -o jsonpath='{.data.status}' \| base64 -d` | `joined` |
| Secondary on the primary | `oc --context <PRIMARY_CONTEXT> -n kasten-io-mc get clusters.dist.kio.kasten.io` | `ocp-secondary` |
| AWS secret tags | `aws secretsmanager describe-secret --region <region> --secret-id <remoteKey> --query Tags` | `managed-by=external-secrets` |

The join check shows only the `status` key. Never print `mc-join`, the
join-token Secret or the AWS secret value.

## 5. Rotate or revoke the join token

- Rotate: increase `handoff.token.generation` in
  `flux/MCM/clusters/ocp-primary/handoff.yaml`.
- Revoke: set `handoff.token.enabled` and `handoff.push.enabled` to `false`.

A rotation also revokes the old token, in the same step. Each joined
secondary gets the new token on its next refresh (5 minutes or less) and
joins again under the same cluster ID. Check that `mc-join-status` shows
`joined` on each secondary.

A secondary uses the join token only to join. After that, it uses its own
session token. If a secondary misses a rotation, for example because ESO is
down, it stays connected. It joins again when it gets the new token.

To join a disconnected secondary again, rotate the token. Kasten does not
start a new join with a token it has already used.

## 6. Rotate an IAM access key

See [aws.md](aws.md), section 7.

## 7. Teardown (in this order)

1. Disconnect the secondary:
   `oc --context <PRIMARY_CONTEXT> -n kasten-io-mc delete clusters.dist.kio.kasten.io ocp-secondary`
2. Remove the secondary's Flux stages: join, then pull, then kasten.
   Kasten deletes `mc-cluster-info` when you disconnect. Removing the pull
   stage deletes `mc-join` and `mc-join-status`.
3. On the primary, revoke the token (step 5), then remove the handoff
   stage. Do not turn off multi-cluster while a secondary is connected.
4. Delete `kasten-io-mc` while Kasten still runs. Helm keeps this namespace.
   Kasten puts finalizers on its `Cluster` objects. If Kasten is already
   gone, clear them first:
   `oc --context <PRIMARY_CONTEXT> -n kasten-io-mc patch clusters.dist.kio.kasten.io <name> --type=merge -p '{"metadata":{"finalizers":null}}'`
5. Remove the primary's kasten stage.
6. Remove the AWS resources: [aws.md](aws.md), section 8.

Removing a stage from Git uninstalls its Helm release, because the stages
use `prune: true`. Deleting the `FluxInstance` or a HelmRelease does the
same. To remove Kasten, remove its stage. Do not delete Flux objects by
hand if you want to keep Kasten.

## Troubleshooting

To read the join result on the secondary:

```bash
oc --context <SECONDARY_CONTEXT> -n kasten-io get secret mc-join-status -o jsonpath='{.data.status}{"\n"}{.data.msg}' | base64 -d
```

| You see | Cause | Do this |
|---|---|---|
| "Cannot find the Kasten dashboard URL" | Stage 1 is not Ready, so `k10-route` does not exist | Wait for `kasten-mc-kasten`, or set the URL value |
| PushSecret: `secret not managed by external-secrets` | Someone created the AWS secret without the ESO tag | Add the tag `managed-by=external-secrets` ([aws.md](aws.md), section 4), or delete the secret and let ESO create it |
| PushSecret: AccessDenied on `DeleteResourcePolicy` | The writer policy does not have this action | Set the writer policy again ([aws.md](aws.md), section 3) |
| PushSecret: AccessDenied on `CreateSecret` | The tag condition did not match | Check the tag that ESO sends. Remove the condition if you must. |
| PushSecret fails after you deleted the AWS secret | AWS keeps the name during the recovery window | Run `aws secretsmanager restore-secret`, or force-delete and wait |
| PushSecret still fails after you fix the AWS credentials | ESO waits longer between each retry after an error (7 minutes and more). It does not watch the credential Secret. | Wait for the next retry, or restart ESO to retry now: `oc --context <CTX> -n external-secrets rollout restart deployment/external-secrets` |
| PushSecret shows one `Errored` event, `secret key token does not exist`, at first install | Kasten fills the token a few seconds after the Secret exists | Nothing. ESO retries and the next event is `Synced`. |
| Store is Ready, but push or pull fails | With access keys, Ready does not check IAM | Read the PushSecret or ExternalSecret status |
| `kasten-mc-pull` stays not Ready | No token yet, or the reader policy is wrong | Check the primary's PushSecret first |
| Join fails with a certificate error | The secondary does not trust the primary's CA | See "Private or self-signed ingress certificates" |
| `mc-join-status` is `rejected` with `Invalid join token` | The secondary has a revoked or old token | Check that the primary's PushSecret and the secondary's ExternalSecret are Ready. The secondary joins when it gets the current token. |
| `mc-join-status` is `rejected` for a duplicate name | Another cluster uses the same `clusterName` | Use a unique `clusterName` |
| `mc-join-status` is `joined`, but the primary does not list the secondary | The secondary was disconnected. Kasten does not update the status. | Rotate the token to join again (step 5) |
| `create-access-key` fails | The user already has 2 keys | Delete a key you do not use |
