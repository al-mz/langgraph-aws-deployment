# LangGraph AWS Deployment - Troubleshooting Guide

This guide helps you diagnose and resolve common issues when deploying LangGraph agents to AWS.

## Quick Diagnostics

### Health Check Commands

```bash
# Check if application is running locally
curl http://localhost:8000/health

# Check if ALB is responding
curl http://<alb-dns-name>/health

# Check ECS service status
aws ecs describe-services --cluster <cluster-name> --services <service-name>

# View recent logs
aws logs tail /ecs/<environment>-langgraph --follow --since 10m
```

## Common Issues and Solutions

### 1. Deployment Script Failures

#### Issue: "AWS CLI not found"
```
Error: AWS CLI is not installed
```

**Solution:**
```bash
# Install AWS CLI v2
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /

# Verify installation
aws --version
```

#### Issue: "AWS credentials not configured"
```
Error: Unable to locate credentials
```

**Solution:**
```bash
# Configure AWS credentials
aws configure

# Or set environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
```

#### Issue: "Docker not running"
```
Error: Cannot connect to the Docker daemon
```

**Solution:**
```bash
# Start Docker Desktop (macOS/Windows)
# Or start Docker daemon (Linux)
sudo systemctl start docker

# Verify Docker is running
docker ps
```

### 2. ECR Issues

#### Issue: "Repository does not exist"
```
Error: The repository with name 'langgraph-development' does not exist
```

**Solution:**
```bash
# Create ECR repository
./aws/scripts/setup-ecr.sh development

# Or manually create
aws ecr create-repository --repository-name langgraph-development
```

#### Issue: "Authentication token has expired"
```
Error: no basic auth credentials
```

**Solution:**
```bash
# Re-authenticate with ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
```

#### Issue: "Image push failed"
```
Error: denied: User is not authorized to perform: ecr:BatchCheckLayerAvailability
```

**Solution:**
Check IAM permissions. Your user/role needs:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:CompleteLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:InitiateLayerUpload",
                "ecr:PutImage"
            ],
            "Resource": "*"
        }
    ]
}
```

### 3. CloudFormation Issues

#### Issue: "Stack already exists"
```
Error: Stack [langgraph-development-vpc] already exists
```

**Solution:**
```bash
# Update existing stack
aws cloudformation deploy --template-file aws/cloudformation/vpc-stack.yaml \
  --stack-name langgraph-development-vpc \
  --parameter-overrides Environment=development

# Or delete and recreate
aws cloudformation delete-stack --stack-name langgraph-development-vpc
aws cloudformation wait stack-delete-complete --stack-name langgraph-development-vpc
```

#### Issue: "Insufficient permissions"
```
Error: User is not authorized to perform: cloudformation:CreateStack
```

**Solution:**
Add CloudFormation permissions to your IAM user/role:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudformation:*",
                "iam:*",
                "ec2:*",
                "ecs:*",
                "elasticloadbalancing:*"
            ],
            "Resource": "*"
        }
    ]
}
```

#### Issue: "CREATE_FAILED - The VPC does not have any internet gateway"
```
Error: The VPC '...' does not have any internet gateway
```

**Solution:**
This usually indicates the VPC stack didn't deploy completely. Check the CloudFormation console for the actual error and redeploy the VPC stack.

### 4. ECS Service Issues

#### Issue: "Tasks are not starting"
```
Service has reached a steady state with 0 running tasks
```

**Debug Steps:**
```bash
# 1. Check service events
aws ecs describe-services --cluster <cluster-name> --services <service-name> \
  --query 'services[0].events' --output table

# 2. Check task definition
aws ecs describe-task-definition --task-definition <task-def-arn>

# 3. Check stopped tasks
aws ecs list-tasks --cluster <cluster-name> --desired-status STOPPED
aws ecs describe-tasks --cluster <cluster-name> --tasks <task-arn>
```

**Common Causes:**
- Insufficient CPU/memory allocation
- Image pull failures
- Security group blocking container port
- Parameter Store access issues

#### Issue: "Task stopped with exit code 1"
```
Task stopped at: <timestamp>
Stopped reason: Essential container in task exited
```

**Solution:**
```bash
# Check container logs
aws logs tail /ecs/<environment>-langgraph --follow

# Common fixes:
# 1. Check if OpenAI API key is set correctly
# 2. Verify all environment variables
# 3. Check application startup code
```

#### Issue: "Health check failures"
```
Target health check failed
```

**Debug Steps:**
```bash
# 1. Test health endpoint directly on task
# Get task private IP
aws ecs describe-tasks --cluster <cluster> --tasks <task-arn> \
  --query 'tasks[0].attachments[0].details[?name==`privateIPv4Address`].value' --output text

# 2. Test from within VPC (if you have access)
curl http://<task-private-ip>:8000/health

# 3. Check security groups
aws ec2 describe-security-groups --group-ids <ecs-security-group-id>
```

### 5. Parameter Store Issues

#### Issue: "Parameter not found"
```
Error: ParameterNotFound
```

**Solution:**
```bash
# List all parameters
./aws/scripts/manage-secrets.sh list development

# Set missing parameter
./aws/scripts/manage-secrets.sh put /langgraph/development/openai-api-key "your-key"

# Verify parameter exists
aws ssm get-parameter --name "/langgraph/development/openai-api-key"
```

#### Issue: "Access denied to parameter"
```
Error: User is not authorized to perform: ssm:GetParameter
```

**Solution:**
Add SSM permissions to ECS task role:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:GetParameter",
                "ssm:GetParameters",
                "ssm:GetParametersByPath"
            ],
            "Resource": "arn:aws:ssm:*:*:parameter/langgraph/*"
        }
    ]
}
```

### 6. Load Balancer Issues

#### Issue: "503 Service Unavailable"
```
<html><body><h1>503 Service Temporarily Unavailable</h1></body></html>
```

**Causes and Solutions:**
1. **No healthy targets**
   ```bash
   # Check target group health
   aws elbv2 describe-target-health --target-group-arn <target-group-arn>
   ```

2. **Security group blocking traffic**
   ```bash
   # Verify ALB security group allows traffic on port 80/443
   # Verify ECS security group allows traffic from ALB security group on port 8000
   ```

3. **Health check configuration**
   ```bash
   # Check health check settings
   aws elbv2 describe-target-groups --target-group-arns <target-group-arn>
   ```

#### Issue: "ALB not accessible from internet"
```
This site can't be reached
```

**Solution:**
1. Check ALB is internet-facing
2. Verify public subnets have route to Internet Gateway
3. Check security group allows inbound traffic on port 80/443

### 7. Application-Specific Issues

#### Issue: "OpenAI API rate limits"
```
Error: Rate limit reached for requests
```

**Solution:**
1. Implement request throttling in the application
2. Add retry logic with exponential backoff
3. Consider using different API keys for different environments

#### Issue: "Memory leaks in long-running sessions"
```
Container killed due to memory usage
```

**Solution:**
1. Implement session cleanup in `simple_agent.py`
2. Add memory monitoring
3. Increase task memory allocation if needed

#### Issue: "Agent timeout errors"
```
Error: Agent processing timed out
```

**Solution:**
1. Increase `AGENT_TIMEOUT` in configuration
2. Optimize agent processing logic
3. Implement async processing for long-running requests

### 8. Networking Issues

#### Issue: "NAT Gateway charges are high"
```
Unexpected NAT Gateway costs
```

**Solution:**
1. Review VPC Flow Logs to identify traffic patterns
2. Consider VPC endpoints for AWS services
3. Optimize outbound traffic

#### Issue: "Cross-AZ traffic costs"
```
High data transfer costs
```

**Solution:**
1. Ensure load balancer and targets are in same AZ when possible
2. Review application architecture for unnecessary cross-AZ calls

## Debugging Tools and Commands

### CloudWatch Logs Insights

Query for application errors:
```sql
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100
```

Query for health check failures:
```sql
fields @timestamp, @message
| filter @message like /health/
| stats count() by bin(5m)
```

### ECS Exec for Container Access

Enable ECS Exec for debugging:
```bash
# Update service to enable execute command
aws ecs update-service --cluster <cluster> --service <service> --enable-execute-command

# Execute command in running container
aws ecs execute-command --cluster <cluster> --task <task-arn> --container langgraph-container --interactive --command "/bin/bash"
```

### Performance Monitoring

Monitor key metrics:
```bash
# CPU and memory utilization
aws cloudwatch get-metric-statistics --namespace AWS/ECS \
  --metric-name CPUUtilization --dimensions Name=ServiceName,Value=<service-name> \
  --start-time 2024-01-01T00:00:00Z --end-time 2024-01-01T23:59:59Z \
  --period 300 --statistics Average

# Request count and latency
aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB \
  --metric-name RequestCount --dimensions Name=LoadBalancer,Value=<alb-name> \
  --start-time 2024-01-01T00:00:00Z --end-time 2024-01-01T23:59:59Z \
  --period 300 --statistics Sum
```

## Prevention Best Practices

### 1. Infrastructure as Code
- Always use CloudFormation templates
- Version control all infrastructure changes
- Test in development before production

### 2. Monitoring and Alerting
- Set up CloudWatch alarms for key metrics
- Monitor application logs for errors
- Implement health checks at multiple levels

### 3. Security
- Regularly rotate secrets
- Use least privilege IAM policies
- Enable VPC Flow Logs for network monitoring

### 4. Cost Management
- Set up billing alerts
- Regular cost reviews
- Right-size resources based on usage

### 5. Documentation
- Document all configuration changes
- Maintain runbooks for common operations
- Keep troubleshooting knowledge up to date

## Getting Help

### AWS Support Resources
- [AWS Documentation](https://docs.aws.amazon.com/)
- [ECS Troubleshooting Guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/troubleshooting.html)
- [ALB Troubleshooting](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-troubleshooting.html)

### Community Resources
- [AWS re:Post](https://repost.aws/)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/amazon-web-services)
- [AWS Reddit Community](https://reddit.com/r/aws)

### Professional Support
- AWS Support Plans
- AWS Professional Services
- AWS Partner Network consultants

## Logging Issues

If you need to report an issue, please include:

1. **Environment details**:
   - AWS region
   - Environment name (dev/staging/prod)
   - Deployment timestamp

2. **Error details**:
   - Exact error message
   - CloudWatch logs (sanitized)
   - CloudFormation events

3. **Configuration**:
   - Parameter Store settings (without secrets)
   - ECS task definition
   - Security group configurations

4. **Steps to reproduce**:
   - Commands executed
   - Expected vs actual behavior
   - Any workarounds attempted
