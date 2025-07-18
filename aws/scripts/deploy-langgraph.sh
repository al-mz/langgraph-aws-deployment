#!/bin/bash

# LangGraph AWS Automated Deployment Script
# Deploys LangGraph + FastAPI application to AWS using ECS + ECR + ALB + Fargate
# 
# Usage: ./deploy-langgraph.sh [environment] [region]
# Example: ./deploy-langgraph.sh production us-west-2

# Exit on any error
set -e

# Function to check if Docker daemon is running
check_docker() {
    if ! docker info > /dev/null 2>&1; then
        echo "ERROR: Docker daemon is not running. Please start Docker and try again."
        exit 1
    fi
}

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

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(development|staging|production)$ ]]; then
    error_exit "Invalid environment: $ENVIRONMENT. Valid environments: development, staging, production"
fi

# Get AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text) || error_exit "Failed to get AWS account ID. Please check your AWS credentials."

# Get the absolute path of the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "🚀 LangGraph AWS Deployment"
echo "=========================="
echo "Environment: $ENVIRONMENT"
echo "Region: $AWS_REGION"
echo "Account ID: $ACCOUNT_ID"
echo "Project Root: $PROJECT_ROOT"
echo ""

# Check prerequisites
echo "🔍 Checking prerequisites..."
check_docker

# Check required tools
for tool in aws docker jq; do
    if ! command -v $tool &> /dev/null; then
        error_exit "$tool is not installed. Please install it first."
    fi
done

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error_exit "AWS credentials not configured. Please run 'aws configure'."
fi

# Check for OpenAI API key
if [ -z "$OPENAI_API_KEY" ]; then
    if [ -f "$PROJECT_ROOT/.env" ]; then
        echo "📋 Loading environment variables from .env file..."
        export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
    fi
    
    if [ -z "$OPENAI_API_KEY" ]; then
        echo "⚠️  OPENAI_API_KEY not found in environment or .env file"
        read -p "Enter your OpenAI API key: " -s OPENAI_API_KEY
        echo
        export OPENAI_API_KEY
    fi
fi

echo "✅ Prerequisites check passed"
echo ""

# Step 1: Create ECR repository
echo "📦 Creating ECR repository..."
if aws ecr describe-repositories --repository-names $REPOSITORY_NAME --region $AWS_REGION 2>&1 | grep -q "RepositoryNotFoundException"; then
    echo "Creating ECR repository: $REPOSITORY_NAME"
    aws ecr create-repository \
        --repository-name $REPOSITORY_NAME \
        --region $AWS_REGION \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256 \
        --tags Key=Environment,Value="$ENVIRONMENT" \
               Key=Project,Value=LangGraph \
               Key=ManagedBy,Value=CloudFormation > /dev/null || error_exit "Failed to create ECR repository"
    echo "✅ ECR repository created successfully"
else
    echo "✅ Repository $REPOSITORY_NAME already exists"
fi

# Step 2: Login to ECR
echo "🔐 Logging in to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com || error_exit "Failed to login to ECR"
echo "✅ ECR login successful"

# Step 3: Build and push Docker image
echo "🐳 Building and pushing Docker image..."
cd "$PROJECT_ROOT" || error_exit "Project root directory not found"

# Create buildx builder if it doesn't exist
docker buildx create --use 2>/dev/null || true

# Build for linux/amd64 platform (ECS Fargate requirement)
IMAGE_URI="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPOSITORY_NAME:latest"
docker buildx build --platform linux/amd64 \
    -t $IMAGE_URI \
    --push . || error_exit "Failed to build and push Docker image"

echo "✅ Docker image pushed successfully to $IMAGE_URI"

# Step 4: Setup secrets in Parameter Store
echo "🔐 Setting up secrets in Parameter Store..."
aws ssm put-parameter \
    --name "/langgraph/openai-api-key" \
    --value "$OPENAI_API_KEY" \
    --type "SecureString" \
    --description "OpenAI API key for LangGraph agent" \
    --region "$AWS_REGION" \
    --overwrite > /dev/null || error_exit "Failed to store OpenAI API key in Parameter Store"

echo "✅ Secrets configured in Parameter Store"

# Step 5: Deploy VPC stack if it doesn't exist
echo "🌐 Deploying VPC infrastructure..."
if ! aws cloudformation describe-stacks --stack-name ${STACK_PREFIX}-vpc --region ${AWS_REGION} --output text > /dev/null 2>&1; then
    echo "Deploying VPC stack..."
    aws cloudformation deploy \
        --template-file "$PROJECT_ROOT/aws/cloudformation/vpc-stack.yaml" \
        --stack-name ${STACK_PREFIX}-vpc \
        --region ${AWS_REGION} \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides \
            Environment=${ENVIRONMENT} > /dev/null || error_exit "Failed to deploy VPC stack"

    echo "Waiting for VPC stack to complete..."
    aws cloudformation wait stack-create-complete \
        --stack-name ${STACK_PREFIX}-vpc \
        --region ${AWS_REGION} || error_exit "VPC stack creation failed"
    
    echo "✅ VPC stack deployed successfully"
else
    echo "✅ VPC stack already exists"
fi

# Step 6: Deploy ECS stack
echo "🚢 Deploying ECS infrastructure..."
aws cloudformation deploy \
    --template-file "$PROJECT_ROOT/aws/cloudformation/ecs-stack.yaml" \
    --stack-name ${STACK_PREFIX}-ecs \
    --region ${AWS_REGION} \
    --capabilities CAPABILITY_IAM \
    --parameter-overrides \
        Environment=${ENVIRONMENT} \
        ImageURI=${IMAGE_URI} > /dev/null || error_exit "Failed to deploy ECS stack"

echo "✅ ECS stack deployed successfully"

# Step 7: Wait for service to be available
echo "⏳ Waiting for service to be available..."
sleep 45

# Step 8: Get the application URL from CloudFormation outputs
echo "🔍 Retrieving application URL..."
APP_URL=$(aws cloudformation describe-stacks \
    --stack-name ${STACK_PREFIX}-ecs \
    --region ${AWS_REGION} \
    --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' \
    --output text 2>/dev/null) || error_exit "Failed to retrieve application URL"

# Step 9: Force update the ECS service to pick up the new image
echo "🔄 Forcing new deployment of ECS service..."
CLUSTER_NAME="${ENVIRONMENT}-langgraph-cluster"
SERVICE_NAME="${ENVIRONMENT}-langgraph-service"

aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --force-new-deployment \
    --region $AWS_REGION > /dev/null || error_exit "Failed to update ECS service"

echo "✅ ECS service updated with new deployment"

# Step 10: Wait for deployment to complete and test
echo "⏳ Waiting for deployment to stabilize..."
sleep 30

# Test health endpoint
echo "🩺 Testing application health..."
for i in {1..12}; do
    if curl -s -f "${APP_URL}/health" > /dev/null 2>&1; then
        echo "✅ Application is healthy and responding"
        break
    else
        if [ $i -eq 12 ]; then
            error_exit "Application health check failed after 2 minutes"
        fi
        echo "Waiting for application to be ready... (attempt $i/12)"
        sleep 10
    fi
done

# Test a simple chat request
echo "🤖 Testing LangGraph agent..."
CHAT_RESPONSE=$(curl -s -X POST "${APP_URL}/chat" \
    -H "Content-Type: application/json" \
    -d '{"message": "Hello! This is a deployment test.", "session_id": "deployment-test"}' \
    --max-time 30) || error_exit "Failed to test chat endpoint"

if echo "$CHAT_RESPONSE" | jq -e '.response' > /dev/null 2>&1; then
    echo "✅ LangGraph agent is working correctly"
else
    error_exit "LangGraph agent test failed"
fi

echo ""
echo "🎉 Deployment completed successfully!"
echo "=================================="
echo ""
echo "📋 Deployment Information:"
echo "  Environment: $ENVIRONMENT"
echo "  Region: $AWS_REGION"
echo "  Application URL: $APP_URL"
echo ""
echo "🔗 Available Endpoints:"
echo "  Health Check: ${APP_URL}/health"
echo "  API Documentation: ${APP_URL}/docs"
echo "  Chat Endpoint: ${APP_URL}/chat"
echo "  Streaming Chat: ${APP_URL}/chat/stream"
echo "  Agent Info: ${APP_URL}/agent/info"
echo ""
echo "🧪 Test Commands:"
echo "  # Health check"
echo "  curl ${APP_URL}/health"
echo ""
echo "  # Test chat"
echo "  curl -X POST '${APP_URL}/chat' \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"message\": \"Hello!\", \"session_id\": \"test-123\"}'"
echo ""
echo "  # Test streaming"
echo "  curl -X POST '${APP_URL}/chat/stream' \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"message\": \"Tell me a story\", \"session_id\": \"stream-test\"}'"
echo ""
echo "📊 AWS Resources Created:"
echo "  - ECR Repository: $REPOSITORY_NAME"
echo "  - VPC Stack: ${STACK_PREFIX}-vpc"
echo "  - ECS Stack: ${STACK_PREFIX}-ecs"
echo "  - Parameter Store: /langgraph/openai-api-key"
echo ""
echo "🔧 Management Commands:"
echo "  # View ECS service"
echo "  aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION"
echo ""
echo "  # View logs"
echo "  aws logs tail /ecs/${ENVIRONMENT}-langgraph --follow --region $AWS_REGION"
echo ""
echo "  # Scale service"
echo "  aws ecs update-service --cluster $CLUSTER_NAME --service $SERVICE_NAME --desired-count 4 --region $AWS_REGION"
echo ""
echo "🚀 Your LangGraph application is now live and ready for production use!"
