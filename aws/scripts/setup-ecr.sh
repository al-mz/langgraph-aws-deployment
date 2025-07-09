#!/bin/bash

# ECR Repository Setup Script
# Creates and configures ECR repository for the LangGraph application

set -e

# Configuration
ENVIRONMENT=${1:-development}
REGION=${AWS_DEFAULT_REGION:-us-east-1}
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

# Check if repository exists
check_repository_exists() {
    aws ecr describe-repositories \
        --repository-names "$REPOSITORY_NAME" \
        --region "$REGION" \
        >/dev/null 2>&1
}

# Create ECR repository
create_repository() {
    log_info "Creating ECR repository: $REPOSITORY_NAME"
    
    aws ecr create-repository \
        --repository-name "$REPOSITORY_NAME" \
        --region "$REGION" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256 \
        --tags Key=Environment,Value="$ENVIRONMENT" \
               Key=Project,Value=LangGraph \
               Key=ManagedBy,Value=CloudFormation
    
    if [ $? -eq 0 ]; then
        log_success "ECR repository created successfully"
    else
        log_error "Failed to create ECR repository"
        exit 1
    fi
}

# Set lifecycle policy
set_lifecycle_policy() {
    log_info "Setting lifecycle policy for repository: $REPOSITORY_NAME"
    
    # Create lifecycle policy JSON
    cat > /tmp/lifecycle-policy.json << EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep last 10 production images",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["v"],
                "countType": "imageCountMoreThan",
                "countNumber": 10
            },
            "action": {
                "type": "expire"
            }
        },
        {
            "rulePriority": 2,
            "description": "Keep last 5 latest images",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["latest"],
                "countType": "imageCountMoreThan",
                "countNumber": 5
            },
            "action": {
                "type": "expire"
            }
        },
        {
            "rulePriority": 3,
            "description": "Delete untagged images older than 1 day",
            "selection": {
                "tagStatus": "untagged",
                "countType": "sinceImagePushed",
                "countUnit": "days",
                "countNumber": 1
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF

    aws ecr put-lifecycle-policy \
        --repository-name "$REPOSITORY_NAME" \
        --region "$REGION" \
        --lifecycle-policy-text file:///tmp/lifecycle-policy.json
    
    if [ $? -eq 0 ]; then
        log_success "Lifecycle policy set successfully"
    else
        log_warning "Failed to set lifecycle policy"
    fi
    
    # Clean up temporary file
    rm -f /tmp/lifecycle-policy.json
}

# Set repository policy (optional - for cross-account access)
set_repository_policy() {
    if [ "$ENVIRONMENT" = "production" ]; then
        log_info "Setting repository policy for production environment"
        
        # Get current AWS account ID
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Create repository policy JSON
        cat > /tmp/repository-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowPushPull",
            "Effect": "Allow",
            "Principal": {
                "AWS": [
                    "arn:aws:iam::${ACCOUNT_ID}:root"
                ]
            },
            "Action": [
                "ecr:BatchCheckLayerAvailability",
                "ecr:BatchGetImage",
                "ecr:CompleteLayerUpload",
                "ecr:GetDownloadUrlForLayer",
                "ecr:InitiateLayerUpload",
                "ecr:PutImage",
                "ecr:UploadLayerPart"
            ]
        }
    ]
}
EOF

        aws ecr set-repository-policy \
            --repository-name "$REPOSITORY_NAME" \
            --region "$REGION" \
            --policy-text file:///tmp/repository-policy.json
        
        if [ $? -eq 0 ]; then
            log_success "Repository policy set successfully"
        else
            log_warning "Failed to set repository policy"
        fi
        
        # Clean up temporary file
        rm -f /tmp/repository-policy.json
    fi
}

# Get repository information
get_repository_info() {
    log_info "Getting repository information..."
    
    REPOSITORY_INFO=$(aws ecr describe-repositories \
        --repository-names "$REPOSITORY_NAME" \
        --region "$REGION" \
        --query 'repositories[0]' \
        --output json)
    
    REPOSITORY_URI=$(echo "$REPOSITORY_INFO" | jq -r '.repositoryUri')
    REGISTRY_ID=$(echo "$REPOSITORY_INFO" | jq -r '.registryId')
    
    log_success "ECR repository setup completed!"
    echo
    echo "📋 Repository Information:"
    echo "  Repository Name: $REPOSITORY_NAME"
    echo "  Repository URI: $REPOSITORY_URI"
    echo "  Registry ID: $REGISTRY_ID"
    echo "  Region: $REGION"
    echo
    echo "🐳 Docker Commands:"
    echo "  Login: aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REPOSITORY_URI"
    echo "  Build: docker build -t $REPOSITORY_NAME ."
    echo "  Tag: docker tag $REPOSITORY_NAME:latest $REPOSITORY_URI:latest"
    echo "  Push: docker push $REPOSITORY_URI:latest"
    echo
}

# Test ECR login
test_ecr_login() {
    log_info "Testing ECR login..."
    
    aws ecr get-login-password --region "$REGION" | \
        docker login --username AWS --password-stdin \
        $(aws ecr describe-repositories --repository-names "$REPOSITORY_NAME" --region "$REGION" --query 'repositories[0].repositoryUri' --output text) \
        >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "ECR login test successful"
    else
        log_warning "ECR login test failed - please check your Docker and AWS configuration"
    fi
}

# Main function
main() {
    log_info "Setting up ECR repository for LangGraph deployment"
    log_info "Environment: $ENVIRONMENT"
    log_info "Region: $REGION"
    echo
    
    # Check if repository already exists
    if check_repository_exists; then
        log_warning "Repository $REPOSITORY_NAME already exists"
        get_repository_info
    else
        # Create repository and configure it
        create_repository
        set_lifecycle_policy
        set_repository_policy
        get_repository_info
    fi
    
    # Test ECR login
    test_ecr_login
    
    log_success "ECR setup completed successfully!"
}

# Help function
show_help() {
    echo "Usage: $0 [ENVIRONMENT]"
    echo
    echo "Setup ECR repository for LangGraph deployment"
    echo
    echo "Arguments:"
    echo "  ENVIRONMENT    Environment name (development, staging, production)"
    echo "                 Default: development"
    echo
    echo "Environment Variables:"
    echo "  AWS_DEFAULT_REGION    AWS region (default: us-east-1)"
    echo
    echo "Examples:"
    echo "  $0                    # Setup for development"
    echo "  $0 production         # Setup for production"
    echo "  AWS_DEFAULT_REGION=us-west-2 $0 staging"
}

# Parse command line arguments
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

# Validate environment
if [ -n "$1" ] && [[ ! "$1" =~ ^(development|staging|production)$ ]]; then
    log_error "Invalid environment: $1"
    log_error "Valid environments: development, staging, production"
    exit 1
fi

# Check prerequisites
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed. Please install it first."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    log_error "jq is not installed. Please install it first."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Please run 'aws configure'."
    exit 1
fi

# Run main function
main
