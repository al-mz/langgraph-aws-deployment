# LangGraph AWS Deployment Guide

This guide will walk you through deploying a LangGraph agent to AWS using ECS (Elastic Container Service) with Fargate.

## Architecture Overview

The deployment architecture includes:

- **Application Layer**: FastAPI application with LangGraph agent
- **Container Layer**: Docker containerized application
- **Compute Layer**: ECS Fargate for serverless container execution
- **Network Layer**: VPC with public/private subnets across 2 AZs
- **Load Balancer**: Application Load Balancer for high availability
- **Storage Layer**: Parameter Store for secrets management
- **Container Registry**: ECR for Docker image storage

## Prerequisites

### Required Tools

1. **AWS CLI** (v2.0+)
   ```bash
   # Install AWS CLI
   curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
   sudo installer -pkg AWSCLIV2.pkg -target /
   
   # Configure AWS credentials
   aws configure
   ```

2. **Docker** (20.0+)
   ```bash
   # Install Docker Desktop
   # Download from: https://www.docker.com/products/docker-desktop
   
   # Verify installation
   docker --version
   ```

3. **jq** (for JSON processing)
   ```bash
   # macOS
   brew install jq
   
   # Ubuntu/Debian
   sudo apt-get install jq
   
   # CentOS/RHEL
   sudo yum install jq
   ```

### AWS Permissions

Your AWS user/role needs the following permissions:
- ECS full access
- ECR full access
- CloudFormation full access
- Systems Manager (Parameter Store) access
- IAM role creation
- VPC management
- Application Load Balancer management

### Environment Variables

Set the following environment variables:

```bash
export OPENAI_API_KEY="your-openai-api-key"
export AWS_DEFAULT_REGION="us-east-1"  # or your preferred region
export ENVIRONMENT="development"  # or staging/production
```

## Quick Start

### 1. Clone and Setup

```bash
git clone <repository-url>
cd langgraph-aws-deployment
```

### 2. One-Command Deployment

For development environment:
```bash
./aws/scripts/deploy.sh
```

For production environment:
```bash
./aws/scripts/deploy.sh -e production -r us-west-2
```

### 3. Verify Deployment

The script will output the Application Load Balancer URL. Test the deployment:

```bash
# Health check
curl https://your-alb-url/health

# API documentation
open https://your-alb-url/docs

# Test chat endpoint
curl -X POST "https://your-alb-url/chat" \
     -H "Content-Type: application/json" \
     -d '{"message": "Hello, how are you?"}'
```

## Step-by-Step Deployment

If you prefer manual deployment or need to troubleshoot:

### Step 1: Setup ECR Repository

```bash
./aws/scripts/setup-ecr.sh development
```

### Step 2: Setup Secrets

```bash
./aws/scripts/manage-secrets.sh setup development
```

### Step 3: Build and Push Docker Image

```bash
# Get ECR repository URI
REPO_URI=$(aws ecr describe-repositories --repository-names langgraph-development --query 'repositories[0].repositoryUri' --output text)

# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $REPO_URI

# Build and push
docker build -t langgraph-development .
docker tag langgraph-development:latest $REPO_URI:latest
docker push $REPO_URI:latest
```

### Step 4: Deploy Infrastructure

```bash
# Deploy VPC stack
aws cloudformation deploy \
    --template-file aws/cloudformation/vpc-stack.yaml \
    --stack-name langgraph-development-vpc \
    --parameter-overrides Environment=development

# Deploy ECS stack
aws cloudformation deploy \
    --template-file aws/cloudformation/ecs-stack.yaml \
    --stack-name langgraph-development-ecs \
    --parameter-overrides Environment=development ImageURI=$REPO_URI:latest \
    --capabilities CAPABILITY_IAM
```

## Configuration

### Environment-Specific Settings

#### Development
- 1 ECS task
- Basic logging
- No SSL termination
- Simplified monitoring

#### Staging
- 2 ECS tasks
- Enhanced logging
- SSL termination (requires certificate)
- CloudWatch alarms

#### Production
- 2+ ECS tasks with auto-scaling
- Comprehensive logging and monitoring
- SSL termination with WAF
- Enhanced security groups
- Multi-AZ deployment

### Application Configuration

Key configuration parameters in `app/config.py`:

```python
# API Configuration
API_HOST = "0.0.0.0"
API_PORT = 8000

# Agent Configuration
OPENAI_MODEL = "gpt-4"
AGENT_TIMEOUT = 30
MAX_ITERATIONS = 10

# AWS Configuration
USE_PARAMETER_STORE = True  # Use for production
AWS_DEFAULT_REGION = "us-east-1"
```

### Parameter Store Configuration

Secrets are managed in AWS Parameter Store:

```bash
# View all parameters
./aws/scripts/manage-secrets.sh list development

# Set individual parameter
./aws/scripts/manage-secrets.sh put /langgraph/development/new-key "value"

# Backup parameters
./aws/scripts/manage-secrets.sh backup development backup.json
```

## Monitoring and Maintenance

### CloudWatch Logs

View application logs:
```bash
aws logs tail /ecs/development-langgraph --follow
```

### ECS Service Management

```bash
# Check service status
aws ecs describe-services --cluster development-langgraph-cluster --services development-langgraph-service

# Update service (after new image push)
aws ecs update-service --cluster development-langgraph-cluster --service development-langgraph-service --force-new-deployment
```

### Auto Scaling

The ECS service includes auto-scaling based on:
- CPU utilization (target: 70%)
- Memory utilization (target: 80%)
- Scale out/in cooldown: 5 minutes

### Health Checks

- **Load Balancer**: `/health` endpoint
- **ECS Task**: Container health check
- **Application**: Internal health monitoring

## Security Considerations

### Network Security
- Private subnets for ECS tasks
- NAT Gateways for outbound internet access
- Security groups with minimal required ports
- VPC Flow Logs (enable in production)

### Application Security
- Non-root container user
- Read-only filesystem where possible
- Secrets in Parameter Store (encrypted)
- IAM roles with least privilege

### SSL/TLS
For production, add SSL certificate:

1. Request certificate in AWS Certificate Manager
2. Update ALB listener to use HTTPS
3. Redirect HTTP to HTTPS

## Troubleshooting

### Common Issues

#### 1. ECS Tasks Not Starting
```bash
# Check ECS events
aws ecs describe-services --cluster <cluster-name> --services <service-name>

# Check CloudWatch logs
aws logs tail /ecs/<environment>-langgraph --follow
```

#### 2. Health Check Failures
- Verify application starts correctly locally
- Check security group allows health check traffic
- Ensure health endpoint returns 200 status

#### 3. Parameter Store Access Issues
- Verify ECS task role has SSM permissions
- Check parameter names and paths
- Ensure encryption key access

#### 4. Docker Build Issues
- Check Dockerfile syntax
- Verify base image availability
- Review build logs for dependency issues

### Debug Commands

```bash
# Local development
docker-compose up --build

# Check ECS task definition
aws ecs describe-task-definition --task-definition <task-definition-arn>

# View parameter store values
./aws/scripts/manage-secrets.sh get /langgraph/development/openai-api-key

# Test load balancer health
curl -v http://<alb-dns-name>/health
```

## Cost Optimization

### Development Environment
- Use smaller instance sizes (512 CPU, 1024 Memory)
- Single AZ deployment
- Minimal retention periods

### Production Environment
- Right-size based on actual usage
- Use Spot instances where appropriate
- Set up CloudWatch billing alerts
- Regular cost reviews

### Estimated Costs (Monthly)

**Development**:
- ECS Fargate: ~$25-50
- ALB: ~$20
- NAT Gateway: ~$45
- Parameter Store: ~$1
- **Total: ~$91-116/month**

**Production**:
- ECS Fargate: ~$100-200
- ALB: ~$20
- NAT Gateway: ~$90 (2 AZs)
- Parameter Store: ~$1
- **Total: ~$211-311/month**

## Next Steps

1. **Custom Domain**: Set up Route 53 for custom domain
2. **SSL Certificate**: Add ACM certificate for HTTPS
3. **CI/CD Pipeline**: Integrate with GitHub Actions or CodePipeline
4. **Monitoring**: Add CloudWatch dashboards and alarms
5. **WAF**: Add Web Application Firewall for production
6. **Backup Strategy**: Implement parameter backup automation

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review CloudWatch logs
3. Open GitHub issue with detailed error information
4. Check AWS service health dashboard
