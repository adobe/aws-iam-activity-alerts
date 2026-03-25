#!/bin/bash

# IAM Activity Alerts - CloudFormation Deployment Script
# This script helps deploy the IAM alerts stack to your AWS account

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
STACK_NAME="iam-activity-alerts"
TEMPLATE_FILE="iam-alerts-cloudformation.yaml"
REGION=""

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if AWS CLI is installed
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        echo "Visit: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
    print_info "AWS CLI found: $(aws --version)"
}

# Function to configure AWS credentials
configure_aws_credentials() {
    echo ""
    print_info "Checking AWS credentials..."

    # Check if credentials are already configured
    if aws sts get-caller-identity &>/dev/null; then
        local identity
        identity=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null)
        print_info "Already authenticated as: ${identity}"
        read -r -p "Do you want to reconfigure credentials? (yes/no) [no]: " reconfigure
        if [ "${reconfigure}" != "yes" ] && [ "${reconfigure}" != "y" ]; then
            return
        fi
    else
        print_warning "No valid AWS credentials found. Please configure them now."
    fi

    echo ""
    echo "Paste your AWS credentials block below, then press Enter twice:"
    echo "(e.g. from AWS SSO: aws_access_key_id=... / aws_secret_access_key=... / aws_session_token=...)"
    echo ""

    aws_access_key_id=""
    aws_secret_access_key=""
    aws_session_token=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && break
        key="${line%%=*}"
        value="${line#*=}"
        case "$key" in
            aws_access_key_id)     aws_access_key_id="$value" ;;
            aws_secret_access_key) aws_secret_access_key="$value" ;;
            aws_session_token)     aws_session_token="$value" ;;
        esac
    done

    if [ -z "$REGION" ]; then
        REGION=$(get_configured_region)
    fi
    read -r -p "AWS Region [${REGION}]: " input
    REGION=${input:-$REGION}

    aws configure set aws_access_key_id "$aws_access_key_id"
    aws configure set aws_secret_access_key "$aws_secret_access_key"
    aws configure set region "$REGION"

    if [ -n "$aws_session_token" ]; then
        aws configure set aws_session_token "$aws_session_token"
        print_info "Session token configured."
    fi

    # Verify credentials work
    if aws sts get-caller-identity &>/dev/null; then
        local identity
        identity=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null)
        print_info "Successfully authenticated as: ${identity}"
    else
        print_error "Credential verification failed. Please check your credentials and try again."
        exit 1
    fi
}

# Function to check if CloudTrail is enabled
check_cloudtrail() {
    print_info "Checking if CloudTrail is enabled..."
    local trails
    trails=$(aws cloudtrail describe-trails --query 'trailList[?IsMultiRegionTrail==`true`]' --output json 2>/dev/null)

    if [ "$trails" == "[]" ]; then
        print_warning "No multi-region CloudTrail found. The alerts require CloudTrail to be enabled."
        print_warning "Please ensure CloudTrail is configured to log management events."
    else
        print_info "CloudTrail is enabled."
    fi
}

# Function to get the configured AWS region, falling back to us-east-1 if invalid
get_configured_region() {
    local region
    region=$(aws configure get region 2>/dev/null)
    if [[ "$region" =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]]; then
        echo "$region"
    else
        echo "us-east-1"
    fi
}

# Function to validate email
validate_email() {
    local email=$1
    if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to get user input
get_parameters() {
    echo ""
    echo "=========================================="
    echo "IAM Activity Alerts - Configuration"
    echo "=========================================="
    echo ""

    # Stack name
    read -r -p "Stack name [${STACK_NAME}]: " input
    STACK_NAME=${input:-$STACK_NAME}

    # AWS Region
    if [ -z "$REGION" ]; then
        REGION=$(get_configured_region)
    fi
    read -r -p "AWS Region [${REGION}]: " input
    REGION=${input:-$REGION}

    # Notification method
    echo ""
    echo "Choose notification method:"
    echo "1) Email only"
    echo "2) Slack only"
    echo "3) Both email and Slack"
    read -r -p "Selection [1-3]: " notification_choice

    EMAIL=""
    WEBHOOK=""

    case $notification_choice in
        1)
            while true; do
                read -r -p "Email address: " EMAIL
                if validate_email "$EMAIL"; then
                    break
                else
                    print_error "Invalid email format. Please try again."
                fi
            done
            ;;
        2)
            read -r -p "Slack Webhook URL: " WEBHOOK
            ;;
        3)
            while true; do
                read -r -p "Email address: " EMAIL
                if validate_email "$EMAIL"; then
                    break
                else
                    print_error "Invalid email format. Please try again."
                fi
            done
            read -r -p "Slack Webhook URL: " WEBHOOK
            ;;
        *)
            print_error "Invalid selection"
            exit 1
            ;;
    esac

    # Excluded usernames
    echo ""
    read -r -p "Excluded usernames (comma-separated, leave empty for none): " EXCLUDED_USERS

    # Alert rule name
    read -r -p "Alert rule name [iam-user-creation-alert]: " input
    ALERT_RULE_NAME=${input:-iam-user-creation-alert}
}

# Function to build parameters array
build_parameters() {
    PARAMS=(
        "ParameterKey=ExcludedUserNames,ParameterValue=${EXCLUDED_USERS}"
        "ParameterKey=AlertRuleName,ParameterValue=${ALERT_RULE_NAME}"
    )

    if [ -n "$EMAIL" ]; then
        PARAMS+=("ParameterKey=NotificationEmail,ParameterValue=${EMAIL}")
    else
        PARAMS+=("ParameterKey=NotificationEmail,ParameterValue=")
    fi

    if [ -n "$WEBHOOK" ]; then
        PARAMS+=("ParameterKey=SlackWebhookUrl,ParameterValue=${WEBHOOK}")
    else
        PARAMS+=("ParameterKey=SlackWebhookUrl,ParameterValue=")
    fi
}

# Function to deploy stack
deploy_stack() {
    print_info "Deploying CloudFormation stack: ${STACK_NAME}"
    print_info "Region: ${REGION}"

    # Check if stack exists
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
        print_warning "Stack already exists. Updating..."
        OPERATION="update-stack"
    else
        print_info "Creating new stack..."
        OPERATION="create-stack"
    fi

    # Deploy using array to avoid eval/injection risk
    aws cloudformation "$OPERATION" \
        --stack-name "$STACK_NAME" \
        --template-body file://"$TEMPLATE_FILE" \
        --parameters "${PARAMS[@]}" \
        --capabilities CAPABILITY_IAM \
        --region "$REGION"

    print_info "Stack deployment initiated successfully!"
    print_info "Waiting for stack to complete..."

    if [ "$OPERATION" == "create-stack" ]; then
        aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region "$REGION"
    else
        aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME" --region "$REGION" 2>/dev/null || true
    fi

    print_info "Stack deployment completed!"

    if [ -n "$EMAIL" ]; then
        echo ""
        print_warning "IMPORTANT: Check your email and confirm the SNS subscription!"
    fi

    echo ""
    print_info "Stack outputs:"
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs' \
        --output table
}

# Function to show summary
show_summary() {
    echo ""
    echo "=========================================="
    echo "Deployment Summary"
    echo "=========================================="
    echo "Stack Name: ${STACK_NAME}"
    echo "Region: ${REGION}"
    echo "Email: ${EMAIL:-Not configured}"
    echo "Slack: ${WEBHOOK:+Configured}${WEBHOOK:-Not configured}"
    echo "Excluded Users: ${EXCLUDED_USERS:-None}"
    echo "Alert Rule: ${ALERT_RULE_NAME}"
    echo "=========================================="
    echo ""
    read -r -p "Proceed with deployment? (yes/no): " confirm

    if [ "$confirm" != "yes" ] && [ "$confirm" != "y" ]; then
        print_warning "Deployment cancelled."
        exit 0
    fi
}

# Main execution
main() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  IAM Activity Alerts Deployment        ║"
    echo "║  CloudFormation Stack Setup            ║"
    echo "╚════════════════════════════════════════╝"
    echo ""

    check_aws_cli
    configure_aws_credentials
    check_cloudtrail
    get_parameters
    build_parameters
    show_summary
    deploy_stack

    echo ""
    print_info "Deployment complete!"
    echo ""
    echo "=========================================="
    echo "Next Steps"
    echo "=========================================="
    echo ""
    if [ -n "$EMAIL" ]; then
        echo "1. Confirm your SNS email subscription"
        echo "   AWS sent a confirmation email to: ${EMAIL}"
        echo "   You MUST click the confirmation link before alerts will be delivered."
        echo ""
    fi
    echo "2. Verify the alert pipeline works end-to-end"
    echo "   Each command below triggers a monitored IAM event, which flows through:"
    echo "   CloudTrail -> EventBridge rule -> Lambda -> SNS/Slack notification"
    echo ""
    echo "   --- Test 1: CreateUser ---"
    echo "   Triggers an alert when a new IAM user is created."
    echo "     aws iam create-user --user-name test-alert-user"
    echo ""
    echo "   --- Test 2: CreateAccessKey ---"
    echo "   Triggers an alert when programmatic credentials are issued for a user."
    echo "     aws iam create-access-key --user-name test-alert-user"
    echo ""
    echo "   --- Test 3: CreateLoginProfile ---"
    echo "   Triggers an alert when console (password) access is enabled for a user."
    echo "     aws iam create-login-profile --user-name test-alert-user --password 'TempPass123!' --no-password-reset-required"
    echo ""
    echo "   --- Cleanup (run after testing) ---"
    echo "   Delete the access key (get the key ID from the CreateAccessKey output):"
    echo "     aws iam delete-access-key --user-name test-alert-user --access-key-id <AccessKeyId>"
    echo "   Delete the login profile:"
    echo "     aws iam delete-login-profile --user-name test-alert-user"
    echo "   Delete the test user:"
    echo "     aws iam delete-user --user-name test-alert-user"
    echo ""
    echo "3. Check CloudWatch Logs if you don't receive an alert"
    echo "   The Lambda function logs to:"
    echo "     /aws/lambda/${ALERT_RULE_NAME}"
    echo ""
    echo "   View recent logs:"
    echo "     aws logs tail /aws/lambda/${ALERT_RULE_NAME} --follow --region ${REGION}"
    echo ""
    echo "=========================================="
    echo "Stack Management"
    echo "=========================================="
    echo ""
    echo "View stack status:"
    echo "  aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query 'Stacks[0].StackStatus'"
    echo ""
    echo "Tear down all resources:"
    echo "  Use the included teardown script for a guided removal (recommended):"
    echo "    ./teardown.sh"
    echo ""
    echo "  Or manually via AWS CLI:"
    echo "    aws cloudformation delete-stack --stack-name ${STACK_NAME} --region ${REGION}"
    echo "    aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME} --region ${REGION}"
    echo ""
}

# Run main function
main
