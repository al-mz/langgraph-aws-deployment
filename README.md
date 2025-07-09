# LangGraph AWS Deployment Template

🚀 **Production-ready template for deploying LangGraph agents to AWS using ECS Fargate**

This repository provides a complete infrastructure-as-code solution for deploying LangGraph-based AI agents to AWS with enterprise-grade scalability, security, and monitoring.

## ✨ Features

- **🐳 Containerized Deployment**: Docker containers with ECS Fargate
- **🏗️ Infrastructure as Code**: CloudFormation templates for reproducible deployments
- **🔒 Security First**: Encrypted secrets management with Parameter Store
- **📈 Auto Scaling**: Automatic scaling based on CPU/memory utilization
- **🌐 Load Balancing**: Application Load Balancer with health checks
- **📊 Monitoring**: CloudWatch integration for logs and metrics
- **🔧 Developer Friendly**: Local development setup with Docker Compose
- **🤖 Working LangGraph Integration**: Complete FastAPI + LangGraph setup ready to deploy
- **📚 Comprehensive Documentation**: Step-by-step guides and troubleshooting

## 🏛️ Architecture

```
Internet → ALB → ECS Fargate Tasks (Private Subnets) → OpenAI API
                ↓
        CloudWatch Logs & Parameter Store
```

**Key Components:**
- **FastAPI Application** with integrated LangGraph agent
- **LangGraph Workflow** with configurable parameters and streaming support
- **ECS Fargate** for serverless container execution
- **Application Load Balancer** for high availability
- **VPC with public/private subnets** across multiple AZs
- **Parameter Store** for secrets management
- **ECR** for container registry
- **CloudWatch** for monitoring and logging

## 🚀 Quick Start

### Prerequisites

- [Python 3.12+](https://www.python.org/downloads/)
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
- [Docker](https://docs.docker.com/get-docker/)
- [jq](https://stedolan.github.io/jq/) for JSON processing
- OpenAI API key

### 1. Clone and Configure

```bash
git clone https://github.com/your-username/langgraph-aws-deployment.git
cd langgraph-aws-deployment
cp examples/.env.example .env

# Edit with your configuration
export OPENAI_API_KEY="your-openai-api-key"
export AWS_DEFAULT_REGION="us-east-1"
```

### 2. Local Development Setup

The repository includes a fully working LangGraph agent integrated with FastAPI. Follow these steps to run it locally:

```bash
# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Copy environment template and configure
cp examples/.env.example .env
# Edit .env and add your OPENAI_API_KEY

# Test the LangGraph agent locally
python test_complete.py

# Run the FastAPI application
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

The application will be available at:
- **API Documentation**: http://localhost:8000/docs
- **Health Check**: http://localhost:8000/health
- **Agent Info**: http://localhost:8000/agent/info

### 3. Test the Integration

```bash
# Test all endpoints
python test_api.py

# Test individual features
curl -X POST "http://localhost:8000/chat" \
     -H "Content-Type: application/json" \
     -d '{"message": "Hello, how are you?", "session_id": "test-123"}'

# Test streaming endpoint
curl -X POST "http://localhost:8000/chat/stream" \
     -H "Content-Type: application/json" \
     -d '{"message": "Stream me a response!", "session_id": "test-stream"}'
```

### 4. Deploy to AWS

```bash
# One-command deployment to development
./aws/scripts/deploy.sh

# Deploy to production
./aws/scripts/deploy.sh -e production -r us-west-2
```

### 5. Test Your Deployment

```bash
# The script will output your ALB URL
curl https://your-alb-url.elb.amazonaws.com/health

# Test the chat endpoint
curl -X POST "https://your-alb-url.elb.amazonaws.com/chat" \
     -H "Content-Type: application/json" \
     -d '{"message": "Hello, how are you?"}'
```

## 🔌 API Endpoints

The FastAPI application provides the following endpoints:

### Core Endpoints

| Endpoint | Method | Description | Example |
|----------|--------|-------------|---------|
| `/health` | GET | Health check for load balancer | Returns service status |
| `/docs` | GET | Interactive API documentation | Swagger UI |
| `/agent/info` | GET | Get agent capabilities and tools | Agent metadata |

### Chat Endpoints

| Endpoint | Method | Description | Request Body |
|----------|--------|-------------|--------------|
| `/chat` | POST | Process message with LangGraph | `{"message": "Hello", "session_id": "123"}` |
| `/chat/stream` | POST | Stream response from LangGraph | Same as `/chat` but streams chunks |
| `/agent/reset/{session_id}` | POST | Reset agent session | None |

### Example Requests

```bash
# Basic chat
curl -X POST "http://localhost:8000/chat" \
     -H "Content-Type: application/json" \
     -d '{
       "message": "Explain quantum computing",
       "session_id": "user-123",
       "context": {"config": "detailed"}
     }'

# Streaming chat
curl -X POST "http://localhost:8000/chat/stream" \
     -H "Content-Type: application/json" \
     -d '{
       "message": "Tell me a story",
       "session_id": "user-456"
     }'
```

### Response Formats

**Standard Chat Response:**
```json
{
  "response": "LangGraph agent response",
  "session_id": "user-123",
  "metadata": {
    "timestamp": "2025-07-09T14:58:04.248654",
    "config": {"my_configurable_param": "detailed"}
  }
}
```

**Streaming Response (Server-Sent Events):**
```
data: {"type": "chunk", "data": {...}, "session_id": "user-456", "timestamp": "..."}

data: {"type": "complete", "session_id": "user-456", "timestamp": "..."}

data: [DONE]
```

## 📁 Project Structure

```
langgraph-aws-deployment/
├── README.md
├── .gitignore
├── requirements.txt           # Python dependencies with LangGraph/LangChain
├── Dockerfile                 # Container configuration
├── docker-compose.yml         # Local development environment
├── .env                       # Local environment variables
│
├── app/                       # Application code
│   ├── __init__.py
│   ├── main.py               # FastAPI app with LangGraph integration
│   ├── config.py             # Configuration management
│   ├── agents/               # Legacy agent structure (for reference)
│   │   ├── __init__.py
│   │   ├── simple_agent.py
│   │   └── tools.py
│   └── agent/                # LangGraph agent implementation
│       └── src/
│           └── agent/
│               ├── __init__.py
│               └── graph.py   # Working LangGraph workflow
│
├── test_*.py                 # Test scripts for local verification
├── test_api.py              # FastAPI endpoint testing
│
├── aws/                      # AWS infrastructure
│   ├── cloudformation/
│   │   ├── vpc-stack.yaml    # VPC and networking
│   │   └── ecs-stack.yaml    # ECS, ALB, and auto scaling
│   └── scripts/
│       ├── deploy.sh         # Main deployment script
│       ├── setup-ecr.sh      # ECR repository setup
│       └── manage-secrets.sh # Parameter Store management
│
├── docs/                     # Documentation
│   ├── architecture-diagram.png
│   ├── deployment-guide.md
│   └── troubleshooting.md
│
└── examples/                 # Examples and templates
    ├── .env.example          # Environment template
    ├── local-development.md  # Local setup guide
    └── sample-requests.json  # API testing examples
```

## 🛠️ Local Development

### Run Locally with Docker Compose

```bash
# Copy environment template
cp examples/.env.example .env

# Start the application
docker-compose up --build

# Test locally
curl http://localhost:8000/health
curl -X POST "http://localhost:8000/chat" \
     -H "Content-Type: application/json" \
     -d '{"message": "What time is it?"}'
```

### Run Locally with Python

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Run the application
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## 🔧 Configuration

### Environment Variables

Key configuration options:

```bash
# Required
OPENAI_API_KEY=your_openai_api_key

# Optional (with defaults)
ENVIRONMENT=development
OPENAI_MODEL=gpt-4
AGENT_TIMEOUT=30
LOG_LEVEL=INFO
```

### AWS Parameter Store

For production deployments, secrets are managed in AWS Parameter Store:

```bash
# Setup secrets for an environment
./aws/scripts/manage-secrets.sh setup production

# List parameters
./aws/scripts/manage-secrets.sh list production

# Backup/restore parameters
./aws/scripts/manage-secrets.sh backup production backup.json
./aws/scripts/manage-secrets.sh restore production backup.json
```

## 📊 Monitoring

### CloudWatch Integration

- **Application Logs**: Structured logging with correlation IDs
- **Metrics**: CPU, memory, request count, response time
- **Alarms**: Auto scaling triggers and error rate monitoring
- **Dashboards**: Custom CloudWatch dashboards for visualization

### Health Checks

- **Load Balancer**: `/health` endpoint monitoring
- **ECS Service**: Container health checks
- **Application**: Internal health monitoring and metrics

## 🔒 Security

### Network Security
- VPC with public/private subnet architecture
- Security groups with minimal required access
- NAT Gateways for outbound internet access
- No direct internet access to application containers

### Application Security
- Non-root container execution
- Secrets stored in encrypted Parameter Store
- IAM roles with least privilege access
- Input validation and error handling

### Production Hardening
- SSL/TLS termination at load balancer
- Web Application Firewall (WAF) integration
- VPC Flow Logs for network monitoring
- Regular security updates and scanning

## 🚀 Deployment Environments

### Development
- Single ECS task
- Basic monitoring
- Cost-optimized configuration
- HTTP-only (no SSL)

### Staging
- Multi-task deployment
- Enhanced monitoring
- SSL termination
- Production-like configuration

### Production
- Auto-scaling ECS service
- Comprehensive monitoring and alerting
- SSL termination with custom domain
- Enhanced security and compliance

## 💰 Cost Optimization

### Estimated Monthly Costs

**Development Environment:**
- ECS Fargate (1 task): ~$25-40
- ALB: ~$20
- NAT Gateway: ~$45
- CloudWatch/Parameter Store: ~$5
- **Total: ~$95-110/month**

**Production Environment:**
- ECS Fargate (2-5 tasks): ~$100-250
- ALB: ~$20
- NAT Gateway (Multi-AZ): ~$90
- CloudWatch/Parameter Store: ~$10
- **Total: ~$220-370/month**

### Cost Optimization Tips
- Use Spot instances for development
- Right-size CPU/memory allocations
- Implement auto-scaling policies
- Set up billing alerts and cost monitoring

## 🧪 Testing

The repository includes comprehensive test scripts:

- **`test_complete.py`** - Complete LangGraph functionality test
- **`test_api.py`** - FastAPI endpoint integration test
- **`test_basic.py`** - Basic graph structure verification
- **`test_minimal.py`** - Minimal functionality test

Run all tests:
```bash
# Test LangGraph directly
python test_complete.py

# Test FastAPI integration (requires app to be running)
python test_api.py
```

## 📚 Documentation

- **[Deployment Guide](docs/deployment-guide.md)**: Comprehensive deployment instructions
- **[Local Development](examples/local-development.md)**: Local setup and development workflow
- **[Troubleshooting](docs/troubleshooting.md)**: Common issues and solutions
- **[API Examples](examples/sample-requests.json)**: Testing examples and API documentation

## 🛠️ Customization

### Adding New Tools

1. Implement tool function in `app/agents/tools.py`
2. Register in `AVAILABLE_TOOLS` dictionary
3. Update agent logic in `simple_agent.py`
4. Test locally and deploy

### Modifying Agent Behavior

1. Edit system prompt in `_get_system_prompt()`
2. Modify graph structure in `_build_graph()`
3. Add new nodes or edges as needed
4. Update configuration parameters

### Infrastructure Changes

1. Modify CloudFormation templates in `aws/cloudformation/`
2. Update deployment scripts if needed
3. Test changes in development environment
4. Deploy to production with proper change management

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Documentation**: Check the [docs/](docs/) directory
- **Issues**: Open a GitHub issue
- **Discussions**: Use GitHub Discussions for questions
- **AWS Support**: Refer to AWS documentation and support

## 🚧 Roadmap

- [ ] CI/CD pipeline integration (GitHub Actions/CodePipeline)
- [ ] Multi-region deployment support
- [ ] Database integration (RDS/DynamoDB)
- [ ] WebSocket support for real-time interactions
- [ ] Prometheus/Grafana monitoring integration
- [ ] Terraform alternative to CloudFormation
- [ ] Kubernetes deployment option
- [ ] Advanced agent capabilities and tool integrations

---

**⭐ Star this repository if you find it helpful!**

Built with ❤️ for the LangGraph and AWS community.