# ROSA: IAM roles instead of access keys

> The main guide uses on-prem OpenShift with IAM user access keys. This page
> shows what changes on ROSA.

On ROSA with STS, pods can use an IAM role. You store no keys on the
cluster.

| | On-prem (this repository) | ROSA with STS |
|---|---|---|
| Identity | IAM users `kasten-mc-writer` and `kasten-mc-reader` | IAM roles |
| On the cluster | An access key in a Kubernetes Secret | No key. A service-account token that STS exchanges for short-lived credentials. |
| Rotation | You rotate the keys (2 keys per user at most) | Automatic |
| Chart and Flux stages | Same | Same |

## What changes

1. Annotate a service account with `eks.amazonaws.com/role-arn: <role ARN>`.
2. Trust the cluster's OIDC provider in the role's trust policy. Use the
   condition `<oidc>:sub = system:serviceaccount:<namespace>:<name>`.
3. In the store, replace `auth.secretRef` with:

```yaml
auth:
  jwt:
    serviceAccountRef:
      name: <service account>
      namespace: <namespace>
```

Sources:

- Red Hat: <https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws_classic_architecture/4/html/authentication_and_authorization/assuming-an-aws-iam-role-for-a-service-account>
- ESO: <https://external-secrets.io/latest/provider/aws-access/>

Not checked: ESO `serviceAccountRef` on ROSA. Red Hat's guide annotates the
ESO controller's service account instead.
