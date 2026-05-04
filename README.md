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

### 1. AWS CLI

Install the AWS CLI if you haven't already:

- **macOS**: `brew install awscli`
- **Linux**: Follow the [official install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- **Windows**: Use the MSI installer from the link above

Verify it's installed:
```bash
aws --version
```

### 2. AWS Credentials

You need valid AWS credentials with permission to create CloudFormation stacks, IAM roles, EventBridge rules, SNS topics, and Lambda functions.

**Standard credentials** (long-lived access keys):
```bash
aws configure
# Enter your AWS Access Key ID, Secret Access Key, region, and output format
```

**Temporary credentials** (AWS SSO, MFA, or assumed roles):

`aws configure` does not prompt for a session token. If you're using temporary credentials (e.g. copied from the AWS SSO console), paste all three lines individually:
```bash
aws configure set aws_access_key_id YOUR_ACCESS_KEY_ID
aws configure set aws_secret_access_key YOUR_SECRET_ACCESS_KEY
aws configure set aws_session_token YOUR_SESSION_TOKEN
aws configure set region us-east-1
```

Alternatively, the `deploy.sh` script has a built-in credential setup step — you can paste the full credentials block (all three `key=value` lines at once) when prompted.

Verify your credentials are working:
```bash
aws sts get-caller-identity
```
You should see your account ID and IAM principal returned. If this fails, your credentials are invalid or expired.

### 3. CloudTrail

This solution relies on AWS CloudTrail to capture IAM API calls. Ensure a trail exists in your account that logs **management events**:

```bash
aws cloudtrail describe-trails --query 'trailList[*].[name,IsMultiRegionTrail,HomeRegion]' --output table
```

If no trail exists, create one in the AWS Console under **CloudTrail > Create trail** before deploying.

### 4. (Optional) Slack Incoming Webhook URL

Required only if you want Slack notifications. See [Setting Up Slack Webhooks](#setting-up-slack-webhooks) below.

---

## Quick Start

### Interactive Script (Recommended)

The easiest way to deploy is using the interactive script:

```bash
./deploy.sh
```

The script will walk you through the following steps:

1. **AWS credentials** — checks if you're already authenticated. If not, prompts you to paste your credentials block.
2. **CloudTrail check** — verifies a multi-region trail is active.
3. **Stack name** — defaults to `iam-activity-alerts`, press Enter to accept.
4. **AWS region** — defaults to your currently configured region (e.g. `us-east-1`).
5. **Notification method** — choose one:
   - `1` — Email only (enter your email address)
   - `2` — Slack only (enter your webhook URL)
   - `3` — Both email and Slack
6. **Excluded usernames** — comma-separated list of IAM usernames that should NOT trigger alerts (e.g. automated service accounts). Leave empty to alert on all users.
7. **Alert rule name** — defaults to `iam-user-creation-alert`.
8. **Confirmation** — review the summary and type `yes` to deploy.

The script waits for the stack to finish deploying and prints the stack outputs when complete.

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

Use the interactive teardown script to remove all deployed resources:

```bash
./teardown.sh
```

The script lists all stack resources before asking for confirmation, then waits for the deletion to complete.

Alternatively, delete directly with the AWS CLI:
```bash
aws cloudformation delete-stack --stack-name iam-activity-alerts --region us-east-1
```

## Cost

Expected: **< $1/month** for typical usage

- EventBridge: No charge for rules; minimal per-event cost
- Lambda (Slack): Free tier eligible
- SNS (email): First 1,000 emails/month free
- CloudWatch Logs: Minimal charges
