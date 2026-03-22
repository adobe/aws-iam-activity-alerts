# aws-iam-activity-alerts

CloudFormation template for monitoring IAM user creation and access key activities with real-time alerts via email (SNS) and/or Slack.

## Overview

This template sets up automated alerts for critical IAM events:
- **CreateUser** - New IAM user creation
- **CreateAccessKey** - Access key generation
- **CreateLoginProfile** - Console access enablement

Notifications are delivered via email (SNS) and/or Slack, enabling security teams to monitor unauthorized or unexpected IAM activity in real time.

## Use Cases

- **Security Monitoring** - Detect unauthorized IAM user creation in real-time
- **Compliance** - Maintain audit trail for IAM changes
- **Team Awareness** - Keep security teams informed of IAM activities
- **Multi-Account Deployment** - Standardize alerting across AWS Organization

## Files

| File | Description |
|------|-------------|
| `iam-alerts-cloudformation.yaml` | Main CloudFormation template with EventBridge, SNS, and Lambda |
| `deploy.sh` | Interactive deployment script with validation |
| `parameters-example.json` | Sample parameters file for easy deployment |

## Prerequisites

- AWS account with CloudTrail enabled (management events logging)
- AWS CLI installed and configured
- (Optional) Slack Incoming Webhook URL

## Quick Start

### Interactive Script

```bash
./deploy.sh
```

The script prompts for notification method (email, Slack, or both), excluded usernames, and rule name, then deploys the CloudFormation stack.

### AWS CLI

Email notifications:
```bash
aws cloudformation create-stack \
  --stack-name iam-activity-alerts \
  --template-body file://iam-alerts-cloudformation.yaml \
  --parameters \
    ParameterKey=NotificationEmail,ParameterValue=security@example.com \
    ParameterKey=ExcludedUserNames,ParameterValue="service-account1,service-account2" \
  --capabilities CAPABILITY_IAM
```

Slack notifications:
```bash
aws cloudformation create-stack \
  --stack-name iam-activity-alerts \
  --template-body file://iam-alerts-cloudformation.yaml \
  --parameters \
    ParameterKey=SlackWebhookUrl,ParameterValue=https://hooks.slack.com/services/YOUR/WEBHOOK/URL \
    ParameterKey=ExcludedUserNames,ParameterValue="service-account1,service-account2" \
  --capabilities CAPABILITY_IAM
```

Both email and Slack:
```bash
aws cloudformation create-stack \
  --stack-name iam-activity-alerts \
  --template-body file://iam-alerts-cloudformation.yaml \
  --parameters \
    ParameterKey=NotificationEmail,ParameterValue=security@example.com \
    ParameterKey=SlackWebhookUrl,ParameterValue=https://hooks.slack.com/services/YOUR/WEBHOOK/URL \
    ParameterKey=ExcludedUserNames,ParameterValue="service-account1,service-account2" \
  --capabilities CAPABILITY_IAM
```

### Parameters File

Copy `parameters-example.json`, fill in your values, then:

```bash
aws cloudformation create-stack \
  --stack-name iam-activity-alerts \
  --template-body file://iam-alerts-cloudformation.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_IAM
```

## Configuration Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `NotificationEmail` | Email for SNS alerts | (empty) |
| `SlackWebhookUrl` | Slack webhook URL | (empty) |
| `ExcludedUserNames` | Comma-separated usernames to exclude | (empty) |
| `AlertRuleName` | EventBridge rule name | `iam-user-creation-alert` |

## Architecture

1. **EventBridge Rule** - Monitors CloudTrail for IAM events
2. **SNS Topic** (optional) - Email notifications with formatted messages
3. **Lambda Function** (optional) - Slack integration with color-coded alerts
4. **IAM Roles** - Minimal permissions for Lambda execution

## Setting Up Slack Webhooks

1. Visit [https://api.slack.com/apps](https://api.slack.com/apps) and click "Create New App" > "From scratch"
2. Under "Incoming Webhooks", toggle "Activate Incoming Webhooks" to ON
3. Click "Add New Webhook to Workspace", select your channel (e.g., `#security-alerts`), and click "Allow"
4. Copy the webhook URL (format: `https://hooks.slack.com/services/T.../B.../xxx`)

Test it:
```bash
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"IAM Alerts test message"}' \
  https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

## Email Subscription Confirmation

After deploying with an email address, AWS sends a confirmation email from `no-reply@sns.amazonaws.com`. You must click the confirmation link within 3 days before alerts will be delivered.

Verify subscription status:
```bash
aws sns list-subscriptions-by-topic \
  --topic-arn $(aws cloudformation describe-stacks \
    --stack-name iam-activity-alerts \
    --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' \
    --output text)
```

## Alert Information

Each alert includes:
- Event type and timestamp
- Target username
- AWS Account ID and region
- Principal who performed the action (ARN)
- Source IP address

## Testing

```bash
# Create a test user (will trigger alert)
aws iam create-user --user-name test-alert-user

# Wait 1-2 minutes for the alert, then clean up
aws iam delete-user --user-name test-alert-user
```

Ensure `test-alert-user` is not in your excluded users list.

## Sharing Across Teams

**Option A: Share via S3 presigned URL**
```bash
# Upload to a private bucket
aws s3 cp iam-alerts-cloudformation.yaml s3://your-templates-bucket/

# Generate a time-limited presigned URL (valid 7 days)
aws s3 presign s3://your-templates-bucket/iam-alerts-cloudformation.yaml \
  --expires-in 604800
```

**Option B: CloudFormation StackSets** for organization-wide deployment — see [AWS StackSets documentation](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html).

**Option C: Fork or clone this repository** — all files are self-contained.

## Security Notes

- **Slack webhook URL**: Marked `NoEcho` to prevent display in the CloudFormation console and CLI output. However, `NoEcho` does not prevent access via `lambda:GetFunctionConfiguration` — anyone with that permission can read the environment variable. For higher-security environments, store the webhook URL in [SSM Parameter Store (SecureString)](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html) or [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html) and retrieve it at Lambda runtime instead.
- Lambda has minimal IAM permissions (CloudWatch Logs only)
- SNS topic policy restricts publishing to EventBridge only
- No credentials stored or transmitted

## Troubleshooting

### No email alerts received

1. Check subscription status (see [Email Subscription Confirmation](#email-subscription-confirmation) above)
2. Check spam/junk folder — add `no-reply@sns.amazonaws.com` to contacts
3. Verify email address in stack parameters:
   ```bash
   aws cloudformation describe-stacks \
     --stack-name iam-activity-alerts \
     --query 'Stacks[0].Parameters[?ParameterKey==`NotificationEmail`].ParameterValue' \
     --output text
   ```

### No Slack alerts received

1. Test the webhook directly:
   ```bash
   curl -X POST -H 'Content-type: application/json' \
     --data '{"text":"Test message"}' YOUR_WEBHOOK_URL
   ```
2. Check Lambda logs:
   ```bash
   aws logs tail /aws/lambda/iam-user-creation-alert-slack-notifier --follow
   ```

### No alerts at all

1. Verify CloudTrail is enabled and logging management events:
   ```bash
   aws cloudtrail get-trail-status --name YOUR_TRAIL_NAME
   ```
2. Check EventBridge rule is enabled:
   ```bash
   aws events describe-rule --name iam-user-creation-alert
   ```
   Look for `"State": "ENABLED"`.
3. Verify targets:
   ```bash
   aws events list-targets-by-rule --rule iam-user-creation-alert
   ```

### Excluded users still triggering alerts

Check the parameter value (case-sensitive):
```bash
aws cloudformation describe-stacks \
  --stack-name iam-activity-alerts \
  --query 'Stacks[0].Parameters[?ParameterKey==`ExcludedUserNames`].ParameterValue' \
  --output text
```

## Customization

### Add more excluded users

```bash
aws cloudformation update-stack \
  --stack-name iam-activity-alerts \
  --use-previous-template \
  --parameters \
    ParameterKey=ExcludedUserNames,ParameterValue="user1,user2,user3" \
    ParameterKey=NotificationEmail,UsePreviousValue=true \
    ParameterKey=SlackWebhookUrl,UsePreviousValue=true \
    ParameterKey=AlertRuleName,UsePreviousValue=true
```

### Monitor additional IAM events

Edit the `eventName` list in `iam-alerts-cloudformation.yaml`:

```yaml
eventName:
  - CreateUser
  - CreateAccessKey
  - CreateLoginProfile
  - DeleteUser        # add as needed
  - DeleteAccessKey   # add as needed
```

## Cleanup

```bash
aws cloudformation delete-stack --stack-name iam-activity-alerts
```

## Cost

Expected: **< $1/month** for typical usage

- EventBridge: No charge for rules; minimal per-event cost
- Lambda (Slack): Free tier eligible
- SNS (email): First 1,000 emails/month free
- CloudWatch Logs: Minimal charges
