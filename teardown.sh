#!/bin/bash

# IAM Activity Alerts - CloudFormation Teardown Script
# This script removes the IAM alerts stack and all associated AWS resources

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
STACK_NAME="iam-activity-alerts"
REGION=""

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
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

check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed."
        exit 1
    fi
    if ! aws sts get-caller-identity &>/dev/null; then
        print_error "No valid AWS credentials found. Please configure them first."
        exit 1
    fi
}

get_parameters() {
    echo ""
    echo "=========================================="
    echo "IAM Activity Alerts - Teardown"
    echo "=========================================="
    echo ""

    read -r -p "Stack name [${STACK_NAME}]: " input
    STACK_NAME=${input:-$STACK_NAME}

    if [ -z "$REGION" ]; then
        REGION=$(get_configured_region)
    fi
    read -r -p "AWS Region [${REGION}]: " input
    REGION=${input:-$REGION}
}

delete_stack() {
    # Check the stack exists
    if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
        print_warning "Stack '${STACK_NAME}' not found in region '${REGION}'. Nothing to delete."
        exit 0
    fi

    echo ""
    print_warning "This will permanently delete the following CloudFormation stack and all its resources:"
    echo "  Stack: ${STACK_NAME}"
    echo "  Region: ${REGION}"
    echo ""
    print_info "Resources that will be removed:"
    aws cloudformation list-stack-resources \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'StackResourceSummaries[*].[ResourceType,LogicalResourceId,ResourceStatus]' \
        --output table 2>/dev/null || true

    echo ""
    read -r -p "Are you sure you want to delete this stack? (yes/no): " confirm
    if [ "$confirm" != "yes" ] && [ "$confirm" != "y" ]; then
        print_warning "Teardown cancelled."
        exit 0
    fi

    print_info "Deleting CloudFormation stack: ${STACK_NAME}..."
    aws cloudformation delete-stack \
        --stack-name "$STACK_NAME" \
        --region "$REGION"

    print_info "Waiting for stack deletion to complete..."
    if aws cloudformation wait stack-delete-complete \
        --stack-name "$STACK_NAME" \
        --region "$REGION" 2>/dev/null; then
        print_info "Stack '${STACK_NAME}' deleted successfully."
    else
        print_error "Stack deletion may have failed. Check the CloudFormation console for details."
        exit 1
    fi
}

verify_deletion() {
    echo ""
    print_info "Verifying all resources have been removed..."
    local all_clean=true

    # 1. Confirm the CloudFormation stack is gone
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
        print_error "CloudFormation stack '${STACK_NAME}' still exists. Check the console for stuck resources."
        all_clean=false
    else
        print_info "CloudFormation stack removed."
    fi

    # 2. Check for leftover CloudWatch Log Groups (Lambda creates these at runtime; they are not owned by the stack)
    local log_groups
    log_groups=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/lambda/" \
        --region "$REGION" \
        --query "logGroups[?contains(logGroupName, '${STACK_NAME}') || contains(logGroupName, 'iam-')].logGroupName" \
        --output text 2>/dev/null)

    if [ -n "$log_groups" ]; then
        print_warning "The following CloudWatch Log Groups were not removed (Lambda creates these outside of CloudFormation):"
        for lg in $log_groups; do
            echo "  ${lg}"
        done
        echo ""
        read -r -p "Delete these log groups? (yes/no) [no]: " delete_logs
        if [ "$delete_logs" == "yes" ] || [ "$delete_logs" == "y" ]; then
            for lg in $log_groups; do
                aws logs delete-log-group --log-group-name "$lg" --region "$REGION"
                print_info "Deleted log group: ${lg}"
            done
        else
            print_warning "Log groups left in place. You can delete them manually in the CloudWatch console."
        fi
    else
        print_info "No leftover CloudWatch Log Groups found."
    fi

    # 3. Summary
    echo ""
    if [ "$all_clean" = true ]; then
        print_info "All stack resources have been removed successfully."
    else
        print_warning "Some resources may still exist. Review the output above."
    fi
}

main() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  IAM Activity Alerts Teardown          ║"
    echo "║  CloudFormation Stack Removal          ║"
    echo "╚════════════════════════════════════════╝"
    echo ""

    check_aws_cli
    get_parameters
    delete_stack
    verify_deletion

    echo ""
    print_info "Teardown complete."
    echo ""
}

main
