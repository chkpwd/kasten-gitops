# AWS resources

Create these resources in your AWS account before you deploy. You choose
the account, the region and the secret name.

## 1. What you need

| AWS resource | Name in this guide | Purpose |
|---|---|---|
| IAM user | `kasten-mc-writer` | The primary uses it to write the token |
| Inline policy | `kasten-mc-writer` | Create and update one secret (section 3) |
| IAM user | `kasten-mc-reader` | The secondary uses it to read the token |
| Inline policy | `kasten-mc-reader` | Read that secret (section 3) |
| Access key | 1 for each user | Kept only in a Kubernetes Secret on its cluster |

You do not need to create the Secrets Manager secret. The PushSecret on the
primary creates it on the first push and tags it
`managed-by=external-secrets`. You can also create it yourself (section 4).

On each cluster, the access key goes into this Secret:

| Kubernetes Secret | Namespace | Keys |
|---|---|---|
| `kasten-mc-aws-credentials` | `external-secrets` | `access-key-id`, `secret-access-key` |

You need:

- `aws` CLI v2, signed in to your account, with rights to create IAM users,
  inline policies and access keys.
- `oc` with a context for each cluster.
- ESO on each cluster (see the [runbook](runbook.md), section 1).

## 2. Pick your region and secret name

The policies and the chart must use the same values:

| Choice | Default | Set it in |
|---|---|---|
| Region | `us-east-2` | `eso-provider-aws.region` in [`../values/aws.yaml`](../values/aws.yaml) |
| Secret name | `kasten-mc-join-token` | `handoff.remoteKey` in the same file |

The secret name can use letters, digits and `/_+=.@-`, for example
`kasten/prod/join-token`. Do not end it with a hyphen and 6 characters,
because AWS adds those to the ARN.

## 3. Create the resources

Set your values. Change them to yours:

```bash
export AWS_REGION=us-east-2 SECRET_NAME=kasten-mc-join-token PRIMARY_CONTEXT=<primary-context> SECONDARY_CONTEXT=<secondary-context>
```

```bash
export SECRET_ARN="arn:aws:secretsmanager:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):secret:${SECRET_NAME}-??????"
```

AWS adds a hyphen and 6 random characters to each secret ARN. The `-??????`
pattern matches the secret before it exists.

Create the users:

```bash
aws iam create-user --user-name kasten-mc-writer --tags Key=app,Value=kasten-mc
```

```bash
aws iam create-user --user-name kasten-mc-reader --tags Key=app,Value=kasten-mc
```

Give the writer its policy:

```bash
aws iam put-user-policy --user-name kasten-mc-writer --policy-name kasten-mc-writer --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"CreateTaggedByEso\",\"Effect\":\"Allow\",\"Action\":[\"secretsmanager:CreateSecret\",\"secretsmanager:TagResource\"],\"Resource\":\"$SECRET_ARN\",\"Condition\":{\"StringEquals\":{\"aws:RequestTag/managed-by\":\"external-secrets\"}}},{\"Sid\":\"ManageValue\",\"Effect\":\"Allow\",\"Action\":[\"secretsmanager:DescribeSecret\",\"secretsmanager:GetSecretValue\",\"secretsmanager:PutSecretValue\",\"secretsmanager:DeleteResourcePolicy\"],\"Resource\":\"$SECRET_ARN\"}]}"
```

Give the reader its policy:

```bash
aws iam put-user-policy --user-name kasten-mc-reader --policy-name kasten-mc-reader --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"ReadValue\",\"Effect\":\"Allow\",\"Action\":[\"secretsmanager:GetSecretValue\"],\"Resource\":\"$SECRET_ARN\"}]}"
```

Create the writer's access key and put it straight into the primary. The
key stays in shell memory. It is not shown or saved to a file:

```bash
read -r key_id key_secret < <(aws iam create-access-key --user-name kasten-mc-writer --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text) && oc --context "$PRIMARY_CONTEXT" -n external-secrets create secret generic kasten-mc-aws-credentials --from-literal=access-key-id="$key_id" --from-file=secret-access-key=<(printf '%s' "$key_secret"); unset key_id key_secret
```

Do the same for the reader on the secondary:

```bash
read -r key_id key_secret < <(aws iam create-access-key --user-name kasten-mc-reader --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text) && oc --context "$SECONDARY_CONTEXT" -n external-secrets create secret generic kasten-mc-aws-credentials --from-literal=access-key-id="$key_id" --from-file=secret-access-key=<(printf '%s' "$key_secret"); unset key_id key_secret
```

## 4. Optional: create the secret yourself

Create the secret before the first push if you want the smallest writer
policy, or if your team creates all secrets. Give it the tag
`managed-by=external-secrets`. ESO writes only to secrets with this tag.
Without it, every push fails with "secret not managed by external-secrets".

```bash
aws secretsmanager create-secret --region "$AWS_REGION" --name "$SECRET_NAME" --secret-string placeholder --tags Key=managed-by,Value=external-secrets
```

The `placeholder` value is replaced on the first push. ESO reads the
current value before it writes, so give the secret a value.

The writer then does not need `CreateSecret` or `TagResource`. Use this
policy instead of the writer policy in section 3:

```bash
aws iam put-user-policy --user-name kasten-mc-writer --policy-name kasten-mc-writer --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"ManageValue\",\"Effect\":\"Allow\",\"Action\":[\"secretsmanager:DescribeSecret\",\"secretsmanager:GetSecretValue\",\"secretsmanager:PutSecretValue\",\"secretsmanager:DeleteResourcePolicy\"],\"Resource\":\"$SECRET_ARN\"}]}"
```

## 5. Why the policies look like this

- **Writer:** ESO first calls `DescribeSecret`. If the secret does not
  exist, ESO calls `CreateSecret` with the tag `managed-by=external-secrets`.
  The policy allows `CreateSecret` and `TagResource` only with that tag.
  Later pushes use `GetSecretValue` and `PutSecretValue`. ESO also calls
  `DeleteResourcePolicy` on every update, even with no resource policy.
- **Reader:** `GetSecretValue` only.
- **No `DeleteSecret`:** the PushSecret keeps the AWS secret when it goes
  away. You delete it in section 8.

## 6. Check

These commands show names and counts only:

```bash
for u in kasten-mc-writer kasten-mc-reader; do echo "$u: policies=$(aws iam list-user-policies --user-name $u --query PolicyNames --output text) keys=$(aws iam list-access-keys --user-name $u --query 'length(AccessKeyMetadata)' --output text)"; done
```

After the first push, the secret exists with the ESO tag:

```bash
aws secretsmanager describe-secret --region "$AWS_REGION" --secret-id "$SECRET_NAME" --query '{Name:Name,Tags:Tags}'
```

## 7. Rotate an access key

A user can have 2 access keys at most.

1. Note the old key ID: `aws iam list-access-keys --user-name kasten-mc-writer`
2. Delete the Kubernetes Secret, then run the access-key command from
   section 3 again.
3. Check that the push still works.
4. Delete the old key: `aws iam delete-access-key --user-name kasten-mc-writer --access-key-id <old key ID>`

## 8. Remove everything

Do this only after you disconnect the secondary and remove the Flux stages
(see the [runbook](runbook.md), section 7).

```bash
oc --context "$PRIMARY_CONTEXT" -n external-secrets delete secret kasten-mc-aws-credentials --ignore-not-found
```

```bash
oc --context "$SECONDARY_CONTEXT" -n external-secrets delete secret kasten-mc-aws-credentials --ignore-not-found
```

This deletes the AWS secret with no recovery window. You cannot get it back:

```bash
aws secretsmanager delete-secret --region "$AWS_REGION" --secret-id "$SECRET_NAME" --force-delete-without-recovery
```

Delete each user's keys and policy, then the user:

```bash
for u in kasten-mc-writer kasten-mc-reader; do for k in $(aws iam list-access-keys --user-name $u --query 'AccessKeyMetadata[].AccessKeyId' --output text); do aws iam delete-access-key --user-name $u --access-key-id $k; done; aws iam delete-user-policy --user-name $u --policy-name $u; aws iam delete-user --user-name $u; done
```
