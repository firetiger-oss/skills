# AWS CloudWatch logs

Forward CloudWatch logs to Firetiger by deploying the onboarding CloudFormation stack (ingest + IAM role).
Uses the Step 1 credentials: `$INGEST_URL`, `$USERNAME`, `$PASSWORD`. Requires `which aws` and a chosen
`$REGION`.

## Deploy the onboarding stack

```bash
aws cloudformation create-stack \
  --stack-name firetiger-cloudwatch-logs \
  --template-url https://firetiger-public-$REGION.s3.$REGION.amazonaws.com/ingest/aws/cloudwatch/logs/ingest-and-iam-onboarding.yaml \
  --parameters \
    ParameterKey=FiretigerEndpoint,ParameterValue=$INGEST_URL \
    ParameterKey=FiretigerUsername,ParameterValue=$USERNAME \
    ParameterKey=FiretigerPassword,ParameterValue=$PASSWORD \
    ParameterKey=FiretigerExternalId,ParameterValue=$(uuidgen) \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $REGION
```

## Wait, then read the outputs

```bash
aws cloudformation wait stack-create-complete --stack-name firetiger-cloudwatch-logs --region $REGION
aws cloudformation describe-stacks --stack-name firetiger-cloudwatch-logs \
  --query 'Stacks[0].Outputs' --region $REGION
```

The outputs include the created IAM Role ARN — surface it in the Step 7 summary so the user can confirm the
cross-account role in the Firetiger dashboard if prompted.
