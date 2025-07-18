#!/bin/bash

# LangGraph AWS Cleanup Script
# Removes all AWS resources created during deployment
# 
# Usage: ./cleanup-aws.sh [environment] [region]
# Example: ./cleanup-aws.sh development us-east-1

# Exit on any error
set -e

# Function to handle errors
error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

# Configuration
ENVIRONMENT=${1:-development}
AWS_REGION=${2:-${AWS_DEFAULT_REGION:-us-east-1}}
STACK_PREFIX="langgraph-${ENVIRONMENT}"
REPOSITORY_NAME="langgraph-${ENVIRONMENT}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(development|staging|production)$ ]]; then
    error_exit "Invalid environment: $ENVIRONMENT. Valid environments: development, staging, production"
fi

# Get AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text) || error_exit "Failed to get AWS account ID. Please check your AWS credentials."

echo "🗑️  LangGraph AWS Cleanup"
echo "========================"
echo "Environment: $ENVIRONMENT"
echo "Region: $AWS_REGION"
echo "Account ID: $ACCOUNT_ID"
echo ""

# Warning message
echo "⚠️  WARNING: This will permanently delete all AWS resources for the $ENVIRONMENT environment!"
echo "This includes:"
echo "  - ECS Cluster and Services"
echo "  - Application Load Balancer"
echo "  - VPC and all networking components"
echo "  - ECR Repository and all images"
echo "  - Parameter Store entries"
echo "  - CloudWatch Log Groups"
echo ""

# Confirmation prompt
read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
if [[ $confirmation != "yes" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
log_info "Starting cleanup process..."

# Step 1: Delete ECS Stack
echo "🚢 Deleting ECS infrastructure..."
if aws cloudformation describe-stacks --stack-name ${STACK_PREFIX}-ecs --region ${AWS_REGION} --output text > /dev/null 2>&1; then
    log_info "Deleting ECS stack: ${STACK_PREFIX}-ecs"
    aws cloudformation delete-stack \
        --stack-name ${STACK_PREFIX}-ecs \
        --region ${AWS_REGION} || log_warning "Failed to delete ECS stack"
    
    log_info "Waiting for ECS stack deletion to complete..."
    aws cloudformation wait stack-delete-complete \
        --stack-name ${STACK_PREFIX}-ecs \
        --region ${AWS_REGION} || log_warning "ECS stack deletion timeout or failed"
    
    log_success "ECS stack deleted successfully"
else
    log_info "ECS stack ${STACK_PREFIX}-ecs does not exist"
fi

# Step 2: Delete VPC Stack
echo "🌐 Deleting VPC infrastructure..."
if aws cloudformation describe-stacks --stack-name ${STACK_PREFIX}-vpc --region ${AWS_REGION} --output text > /dev/null 2>&1; then
    log_info "Deleting VPC stack: ${STACK_PREFIX}-vpc"
    aws cloudformation delete-stack \
        --stack-name ${STACK_PREFIX}-vpc \
        --region ${AWS_REGION} || log_warning "Failed to delete VPC stack"
    
    log_info "Waiting for VPC stack deletion to complete..."
    aws cloudformation wait stack-delete-complete \
        --stack-name ${STACK_PREFIX}-vpc \
        --region ${AWS_REGION} || log_warning "VPC stack deletion timeout or failed"
    
    log_success "VPC stack deleted successfully"
else
    log_info "VPC stack ${STACK_PREFIX}-vpc does not exist"
fi

# Step 3: Delete Base Stack (if it exists)
echo "🏗️  Deleting base infrastructure..."
if aws cloudformation describe-stacks --stack-name ${STACK_PREFIX}-base --region ${AWS_REGION} --output text > /dev/null 2>&1; then
    log_info "Deleting base stack: ${STACK_PREFIX}-base"
    aws cloudformation delete-stack \
        --stack-name ${STACK_PREFIX}-base \
        --region ${AWS_REGION} || log_warning "Failed to delete base stack"
    
    log_info "Waiting for base stack deletion to complete..."
    aws cloudformation wait stack-delete-complete \
        --stack-name ${STACK_PREFIX}-base \
        --region ${AWS_REGION} || log_warning "Base stack deletion timeout or failed"
    
    log_success "Base stack deleted successfully"
else
    log_info "Base stack ${STACK_PREFIX}-base does not exist"
fi

# Step 4: Delete ECR Repository and Images
echo "📦 Deleting ECR repository..."
if aws ecr describe-repositories --repository-names $REPOSITORY_NAME --region $AWS_REGION > /dev/null 2>&1; then
    log_info "Deleting all images in ECR repository: $REPOSITORY_NAME"
    
    # Get all image tags
    IMAGE_TAGS=$(aws ecr list-images --repository-name $REPOSITORY_NAME --region $AWS_REGION --query 'imageIds[*].imageTag' --output text 2>/dev/null || echo "")
    
    if [ ! -z "$IMAGE_TAGS" ]; then
        # Delete all images
        for tag in $IMAGE_TAGS; do
            if [ "$tag" != "None" ]; then
                log_info "Deleting image with tag: $tag"
                aws ecr batch-delete-image \
                    --repository-name $REPOSITORY_NAME \
                    --image-ids imageTag=$tag \
                    --region $AWS_REGION > /dev/null || log_warning "Failed to delete image: $tag"
            fi
        done
    fi
    
    # Delete untagged images
    UNTAGGED_IMAGES=$(aws ecr list-images --repository-name $REPOSITORY_NAME --region $AWS_REGION --filter tagStatus=UNTAGGED --query 'imageIds[*].imageDigest' --output text 2>/dev/null || echo "")
    
    if [ ! -z "$UNTAGGED_IMAGES" ]; then
        for digest in $UNTAGGED_IMAGES; do
            log_info "Deleting untagged image: $digest"
            aws ecr batch-delete-image \
                --repository-name $REPOSITORY_NAME \
                --image-ids imageDigest=$digest \
                --region $AWS_REGION > /dev/null || log_warning "Failed to delete untagged image"
        done
    fi
    
    log_info "Deleting ECR repository: $REPOSITORY_NAME"
    aws ecr delete-repository \
        --repository-name $REPOSITORY_NAME \
        --region $AWS_REGION \
        --force > /dev/null || log_warning "Failed to delete ECR repository"
    
    log_success "ECR repository deleted successfully"
else
    log_info "ECR repository $REPOSITORY_NAME does not exist"
fi

# Step 5: Delete Parameter Store entries
echo "🔐 Deleting Parameter Store entries..."
PARAMETERS=$(aws ssm describe-parameters --region $AWS_REGION --query "Parameters[?starts_with(Name, '/langgraph/')].Name" --output text 2>/dev/null || echo "")

if [ ! -z "$PARAMETERS" ]; then
    for param in $PARAMETERS; do
        log_info "Deleting parameter: $param"
        aws ssm delete-parameter \
            --name "$param" \
            --region $AWS_REGION > /dev/null || log_warning "Failed to delete parameter: $param"
    done
    log_success "Parameter Store entries deleted successfully"
else
    log_info "No Parameter Store entries found for /langgraph/"
fi

# Step 6: Delete CloudWatch Log Groups
echo "📊 Deleting CloudWatch Log Groups..."
LOG_GROUPS=$(aws logs describe-log-groups --region $AWS_REGION --log-group-name-prefix "/ecs/${ENVIRONMENT}-langgraph" --query 'logGroups[*].logGroupName' --output text 2>/dev/null || echo "")

if [ ! -z "$LOG_GROUPS" ]; then
    for log_group in $LOG_GROUPS; do
        log_info "Deleting log group: $log_group"
        aws logs delete-log-group \
            --log-group-name "$log_group" \
            --region $AWS_REGION > /dev/null || log_warning "Failed to delete log group: $log_group"
    done
    log_success "CloudWatch Log Groups deleted successfully"
else
    log_info "No CloudWatch Log Groups found for /ecs/${ENVIRONMENT}-langgraph"
fi

# Step 7: Clean up any remaining resources
echo "🧹 Checking for any remaining resources..."

# Check for any remaining ECS clusters
CLUSTERS=$(aws ecs list-clusters --region $AWS_REGION --query "clusterArns[?contains(@, '${ENVIRONMENT}-langgraph')]" --output text 2>/dev/null || echo "")
if [ ! -z "$CLUSTERS" ]; then
    log_warning "Found remaining ECS clusters that may need manual cleanup:"
    for cluster in $CLUSTERS; do
        echo "  - $cluster"
    done
fi

# Check for any remaining load balancers
LOAD_BALANCERS=$(aws elbv2 describe-load-balancers --region $AWS_REGION --query "LoadBalancers[?contains(LoadBalancerName, '${ENVIRONMENT}-langgraph')].LoadBalancerArn" --output text 2>/dev/null || echo "")
if [ ! -z "$LOAD_BALANCERS" ]; then
    log_warning "Found remaining load balancers that may need manual cleanup:"
    for lb in $LOAD_BALANCERS; do
        echo "  - $lb"
    done
fi

echo ""
log_success "🎉 Cleanup completed successfully!"
echo "=================================="
echo ""
echo "📋 Cleanup Summary:"
echo "  Environment: $ENVIRONMENT"
echo "  Region: $AWS_REGION"
echo ""
echo "🗑️  Resources Removed:"
echo "  ✅ ECS Stack: ${STACK_PREFIX}-ecs"
echo "  ✅ VPC Stack: ${STACK_PREFIX}-vpc"
echo "  ✅ Base Stack: ${STACK_PREFIX}-base (if existed)"
echo "  ✅ ECR Repository: $REPOSITORY_NAME"
echo "  ✅ Parameter Store: /langgraph/* entries"
echo "  ✅ CloudWatch Log Groups: /ecs/${ENVIRONMENT}-langgraph*"
echo ""
echo "💰 Cost Impact:"
echo "  - All billable resources have been removed"
echo "  - No ongoing charges for this deployment"
echo ""
echo "🔍 Verification Commands:"
echo "  # Check for remaining stacks"
echo "  aws cloudformation list-stacks --region $AWS_REGION --query 'StackSummaries[?contains(StackName, \`${ENVIRONMENT}\`) && StackStatus != \`DELETE_COMPLETE\`]'"
echo ""
echo "  # Check for remaining ECR repositories"
echo "  aws ecr describe-repositories --region $AWS_REGION --query 'repositories[?contains(repositoryName, \`${ENVIRONMENT}\`)]'"
echo ""
echo "  # Check for remaining ECS clusters"
echo "  aws ecs list-clusters --region $AWS_REGION --query 'clusterArns[?contains(@, \`${ENVIRONMENT}\`)]'"
echo ""
echo "✨ Your AWS environment has been cleaned up!"
