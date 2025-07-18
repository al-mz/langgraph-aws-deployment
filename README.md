# LangGraph AWS Deployment Template

🚀 **Production-ready template for deploying LangGraph agents to AWS using ECS Fargate**

Complete infrastructure-as-code solution for deploying LangGraph-based AI agents to AWS with auto-scaling, load balancing, and secure secrets management.

## ✨ Features

- **🐳 Containerized Deployment**: Docker + ECS Fargate
- **🏗️ Infrastructure as Code**: CloudFormation templates
- **🔒 Security First**: Encrypted secrets with Parameter Store
- **📈 Auto Scaling**: CPU/memory-based scaling
- **🌐 Load Balancing**: Application Load Balancer with health checks
- **🔧 Developer Friendly**: Local development setup

## 🏛️ Architecture

```
Internet → ALB → ECS Fargate Tasks (Private Subnets) → OpenAI API
                ↓
        CloudWatch Logs & Parameter Store
```

### Deployment Architecture

```mermaid
graph TB
    subgraph "🏗️ Development"
        DEV[Developer] --> LOCAL[Local Testing]
        LOCAL --> DOCKER[Docker Build]
    end
    
    subgraph "☁️ AWS Infrastructure"
        subgraph "🏗️ Foundation"
            ECR[ECR Repository]
            IAM[IAM Roles]
            SSM[Parameter Store]
        end
        
        subgraph "🌐 Network"
            VPC[VPC] --> ALB[Load Balancer]
            ALB --> ECS[ECS Service]
        end
        
        subgraph "🚢 Application"
            ECS --> TASK1[Fargate Task 1]
            ECS --> TASK2[Fargate Task 2]
        end
    end
    
    subgraph "🌍 External"
        USERS[Users] --> ALB
        TASK1 --> OPENAI[OpenAI API]
        TASK2 --> OPENAI
    end
    
    DOCKER --> ECR
    ECR --> ECS
    
    classDef aws fill:#FF9900,stroke:#232F3E,stroke-width:2px,color:#fff
    classDef app fill:#2196F3,stroke:#1565C0,stroke-width:2px,color:#fff
    classDef ext fill:#9C27B0,stroke:#6A1B9A,stroke-width:2px,color:#fff
    
    class ECR,IAM,SSM,VPC,ALB,ECS aws
    class TASK1,TASK2,DOCKER app
    class USERS,OPENAI ext
```

## 🚀 Quick Start

### Prerequisites

- [Python 3.12+](https://www.python.org/downloads/)
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
- [Docker](https://docs.docker.com/get-docker/)
- [jq](https://stedolan.github.io/jq/)
- OpenAI API key

### 1. Setup

```bash
git clone https://github.com/your-username/langgraph-aws-deployment.git
cd langgraph-aws-deployment
cp .env.example .env
# Edit .env with your OpenAI API key
```

### 2. Local Development

```bash
# Create virtual environment
python -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run locally
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### 3. Deploy to AWS

```bash
# Deploy to production
./aws/scripts/deploy-langgraph.sh production us-east-1
```

### 4. Test Deployment

```bash
# Test health endpoint
curl https://your-alb-url.amazonaws.com/health

# Test chat
curl -X POST "https://your-alb-url.amazonaws.com/chat" \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello!", "session_id": "test-123"}'
```

### 5. Cleanup

```bash
# Remove all AWS resources
./cleanup-aws.sh development ca-central-1
```

## 🔌 API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/docs` | GET | API documentation |
| `/chat` | POST | Send message to LangGraph agent |
| `/chat/stream` | POST | Streaming chat response |
| `/agent/info` | GET | Agent metadata |

### Example Usage

```bash
# Basic chat
curl -X POST "http://localhost:8000/chat" \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello!", "session_id": "user-123"}'

# Streaming chat
curl -X POST "http://localhost:8000/chat/stream" \
  -H "Content-Type: application/json" \
  -d '{"message": "Tell me a story", "session_id": "user-456"}'
```

## 📁 Project Structure

```
langgraph-aws-deployment/
├── app/                      # Application code
│   ├── main.py              # FastAPI app
│   ├── config.py            # Configuration
│   └── agent/               # LangGraph agent
├── aws/                     # AWS infrastructure
│   ├── cloudformation/      # CloudFormation templates
│   └── scripts/             # Deployment scripts
├── requirements.txt         # Python dependencies
├── Dockerfile              # Container definition
├── docker-compose.yml      # Local development
└── cleanup-aws.sh          # Cleanup script
```

## 🔧 Configuration

### Environment Variables

```bash
# Required
OPENAI_API_KEY=your_openai_api_key

# Optional
ENVIRONMENT=development
OPENAI_MODEL=gpt-4
LOG_LEVEL=INFO
```

##  Estimated Costs

**Development:**
- ECS Fargate: ~$25-40/month
- ALB: ~$20/month
- NAT Gateway: ~$45/month
- **Total: ~$90-105/month**

**Production:**
- ECS Fargate (2-5 tasks): ~$100-250/month
- ALB: ~$20/month
- NAT Gateway: ~$90/month
- **Total: ~$210-360/month**

## 🗑️ Cleanup

Remove all AWS resources when done:

```bash
./cleanup-aws.sh development ca-central-1
```

## 🛠️ Development

### Local Testing

```bash
# Run with Docker Compose
docker-compose up --build

# Test locally
curl http://localhost:8000/health
```

### Test Scripts

- `test_complete.py` - Complete functionality test
- `test_api.py` - API endpoint tests

## 🔒 Security

- VPC with private subnets
- Encrypted secrets in Parameter Store
- IAM roles with least privilege
- SSL termination at load balancer

## 🆘 Support

- Check the `docs/` directory for detailed guides
- Open GitHub issues for problems
- AWS documentation for AWS-specific issues

---

**Built with ❤️ for the LangGraph community**