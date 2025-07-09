#!/bin/bash

# LangGraph AWS Deployment Script
# This script deploys the entire LangGraph agent infrastructure to AWS

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
REGION=${AWS_DEFAULT_REGION:-us-east-1}
ENVIRONMENT=${ENVIRONMENT:-development}
STACK_PREFIX="langgraph-${ENVIRONMENT}"

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check if required environment variables are set
    if [ -z "$OPENAI_API_KEY" ]; then
        log_warning "OPENAI_API_KEY environment variable not set."
        read -p "Enter your OpenAI API key: " -s OPENAI_API_KEY
        echo
        export OPENAI_API_KEY
    fi
    
    log_success "Prerequisites check passed"
}

# Setup ECR repository
setup_ecr() {
    log_info "Setting up ECR repository..."
    
    # Run ECR setup script
    bash "${SCRIPT_DIR}/setup-ecr.sh" "$ENVIRONMENT"
    
    if [ $? -eq 0 ]; then
        log_success "ECR repository setup completed"
    else
        log_error "ECR repository setup failed"
        exit 1
    fi
}

# Build and push Docker image
build_and_push_image() {
    log_info "Building and pushing Docker image..."
    
    # Get ECR repository URI
    REPOSITORY_URI=$(aws ecr describe-repositories \
        --repository-names "langgraph-${ENVIRONMENT}" \
        --region "$REGION" \
        --query 'repositories[0].repositoryUri' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$REPOSITORY_URI" ]; then
        log_error "ECR repository not found. Please run setup-ecr.sh first."
        exit 1
    fi
    
    # Login to ECR
    aws ecr get-login-password --region "$REGION" | \
        docker login --username AWS --password-stdin "$REPOSITORY_URI"
    
    # Build image
    log_info "Building Docker image..."
    cd "$PROJECT_ROOT"
    docker build -t "langgraph-${ENVIRONMENT}" .
    
    # Tag and push image
    IMAGE_TAG="latest"
    FULL_IMAGE_URI="${REPOSITORY_URI}:${IMAGE_TAG}"
    
    docker tag "langgraph-${ENVIRONMENT}" "$FULL_IMAGE_URI"
    docker push "$FULL_IMAGE_URI"
    
    log_success "Docker image pushed to $FULL_IMAGE_URI"
    echo "$FULL_IMAGE_URI" > /tmp/langgraph-image-uri
}

# Deploy CloudFormation stacks
deploy_infrastructure() {
    log_info "Deploying infrastructure stacks..."
    
    # Deploy VPC stack
    log_info "Deploying VPC stack..."
    aws cloudformation deploy \
        --template-file "${PROJECT_ROOT}/aws/cloudformation/vpc-stack.yaml" \
        --stack-name "${STACK_PREFIX}-vpc" \
        --parameter-overrides \
            Environment="$ENVIRONMENT" \
        --capabilities CAPABILITY_IAM \
        --region "$REGION"
    
    if [ $? -ne 0 ]; then
        log_error "VPC stack deployment failed"
        exit 1
    fi
    
    log_success "VPC stack deployed successfully"
    
    # Get image URI
    if [ -f /tmp/langgraph-image-uri ]; then
        IMAGE_URI=$(cat /tmp/langgraph-image-uri)
    else
        log_error "Image URI not found. Please build and push the image first."
        exit 1
    fi
    
    # Deploy ECS stack
    log_info "Deploying ECS stack..."
    aws cloudformation deploy \
        --template-file "${PROJECT_ROOT}/aws/cloudformation/ecs-stack.yaml" \
        --stack-name "${STACK_PREFIX}-ecs" \
        --parameter-overrides \
            Environment="$ENVIRONMENT" \
            ImageURI="$IMAGE_URI" \
        --capabilities CAPABILITY_IAM \
        --region "$REGION"
    
    if [ $? -ne 0 ]; then
        log_error "ECS stack deployment failed"
        exit 1
    fi
    
    log_success "ECS stack deployed successfully"
}

# Setup secrets in Parameter Store
setup_secrets() {
    log_info "Setting up secrets in Parameter Store..."
    
    # Run secrets management script
    bash "${SCRIPT_DIR}/manage-secrets.sh" put "$ENVIRONMENT"
    
    if [ $? -eq 0 ]; then
        log_success "Secrets setup completed"
    else
        log_error "Secrets setup failed"
        exit 1
    fi
}

# Get deployment outputs
get_outputs() {
    log_info "Getting deployment outputs..."
    
    # Get ALB URL
    ALB_URL=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_PREFIX}-ecs" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$ALB_URL" ]; then
        log_success "Application deployed successfully!"
        echo
        echo "🚀 Deployment Information:"
        echo "  Environment: $ENVIRONMENT"
        echo "  Region: $REGION"
        echo "  Application URL: $ALB_URL"
        echo "  Health Check: ${ALB_URL}/health"
        echo "  API Documentation: ${ALB_URL}/docs"
        echo
        echo "📝 Next Steps:"
        echo "  1. Wait 2-3 minutes for the service to be healthy"
        echo "  2. Test the health endpoint: curl ${ALB_URL}/health"
        echo "  3. Check the API docs at: ${ALB_URL}/docs"
        echo "  4. Send test requests using examples/sample-requests.json"
    else
        log_warning "Could not retrieve ALB URL. Check the AWS console for deployment status."
    fi
}

# Cleanup function
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -f /tmp/langgraph-image-uri
}

# Main deployment function
main() {
    log_info "Starting LangGraph AWS deployment..."
    log_info "Environment: $ENVIRONMENT"
    log_info "Region: $REGION"
    echo
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    # Run deployment steps
    check_prerequisites
    setup_ecr
    build_and_push_image
    setup_secrets
    deploy_infrastructure
    get_outputs
    
    log_success "Deployment completed successfully!"
}

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Deploy LangGraph agent to AWS"
    echo
    echo "Options:"
    echo "  -e, --environment ENV    Set environment (development, staging, production)"
    echo "  -r, --region REGION      Set AWS region (default: us-east-1)"
    echo "  -h, --help              Show this help message"
    echo
    echo "Environment Variables:"
    echo "  OPENAI_API_KEY          OpenAI API key (required)"
    echo "  AWS_DEFAULT_REGION      AWS region (optional)"
    echo "  ENVIRONMENT             Environment name (optional)"
    echo
    echo "Examples:"
    echo "  $0                                    # Deploy to development"
    echo "  $0 -e production -r us-west-2        # Deploy to production in us-west-2"
    echo "  ENVIRONMENT=staging $0               # Deploy to staging"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(development|staging|production)$ ]]; then
    log_error "Invalid environment: $ENVIRONMENT"
    log_error "Valid environments: development, staging, production"
    exit 1
fi

# Run main function
main
