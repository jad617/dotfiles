## Assume role with

```bash
ROLE_ARN="arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>"
TOKEN=$(curl -s "$ACTIONS_ID_TOKEN_REQUEST_URL" \
  -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" | jq -r .value)

CREDENTIALS=$(aws sts assume-role-with-web-identity \
  --role-arn "$ROLE_ARN" \
  --role-session-name github-actions \
  --web-identity-token "$TOKEN" \
  --duration-seconds 900)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r .Credentials.AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r .Credentials.SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r .Credentials.SessionToken)

aws sts get-caller-identity
```
