# Local Development Guide

This guide helps you set up and run the LangGraph agent locally for development and testing.

## Quick Start

### 1. Environment Setup

```bash
# Clone the repository
git clone <repository-url>
cd langgraph-aws-deployment

# Copy environment template
cp examples/.env.example .env

# Edit .env with your configuration
nano .env  # or use your preferred editor
```

### 2. Install Dependencies

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### 3. Run Locally

```bash
# Run with Python directly
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Or run with Docker Compose
docker-compose up --build
```

### 4. Test the Application

```bash
# Health check
curl http://localhost:8000/health

# API documentation
open http://localhost:8000/docs

# Test chat endpoint
curl -X POST "http://localhost:8000/chat" \
     -H "Content-Type: application/json" \
     -d '{"message": "Hello, how are you?"}'
```

## Development Workflow

### Project Structure

```
langgraph-aws-deployment/
├── app/                    # Application code
│   ├── main.py            # FastAPI application
│   ├── config.py          # Configuration management
│   └── agents/            # LangGraph agents
├── aws/                   # AWS infrastructure
├── docs/                  # Documentation
└── examples/              # Example configurations
```

### Environment Variables

Key environment variables for development:

```bash
# Required
OPENAI_API_KEY=your_openai_api_key

# Optional (with defaults)
ENVIRONMENT=development
LOG_LEVEL=DEBUG
API_PORT=8000
OPENAI_MODEL=gpt-4
```

### Docker Development

Use Docker Compose for consistent development environment:

```bash
# Start all services
docker-compose up --build

# Start in background
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down

# Rebuild after code changes
docker-compose up --build
```

### Code Changes and Hot Reload

The application supports hot reload in development mode:

1. **Python direct**: Use `--reload` flag with uvicorn
2. **Docker Compose**: Volume mounts enable live code reloading

### Debugging

#### Python Debugging

Add breakpoints in your code:
```python
import pdb; pdb.set_trace()  # Python debugger
# or
import ipdb; ipdb.set_trace()  # Enhanced debugger (install with pip install ipdb)
```

#### VS Code Debugging

Create `.vscode/launch.json`:
```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "FastAPI",
            "type": "python",
            "request": "launch",
            "program": "${workspaceFolder}/app/main.py",
            "args": [],
            "console": "integratedTerminal",
            "envFile": "${workspaceFolder}/.env"
        }
    ]
}
```

## Testing

### Manual Testing

#### 1. Health Check
```bash
curl http://localhost:8000/health
```

Expected response:
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "environment": "development"
}
```

#### 2. Agent Information
```bash
curl http://localhost:8000/agent/info
```

#### 3. Chat Interaction
```bash
curl -X POST "http://localhost:8000/chat" \
     -H "Content-Type: application/json" \
     -d '{
       "message": "What time is it?",
       "session_id": "test-session"
     }'
```

#### 4. Session Reset
```bash
curl -X POST "http://localhost:8000/agent/reset/test-session"
```

### Automated Testing

Run tests with pytest (if implemented):
```bash
# Install test dependencies
pip install pytest pytest-asyncio httpx

# Run tests
pytest tests/

# Run with coverage
pytest --cov=app tests/
```

### Load Testing

Use tools like Apache Bench or wrk for load testing:

```bash
# Install Apache Bench (ab)
# macOS: brew install httpd
# Ubuntu: sudo apt-get install apache2-utils

# Simple load test
ab -n 100 -c 10 http://localhost:8000/health

# Chat endpoint load test
ab -n 50 -c 5 -p examples/sample-request.json -T application/json http://localhost:8000/chat
```

## Development Best Practices

### Code Organization

1. **Modular Design**: Keep agents, tools, and utilities in separate modules
2. **Configuration**: Use environment variables for all configuration
3. **Error Handling**: Implement comprehensive error handling
4. **Logging**: Use structured logging for debugging

### Agent Development

#### Adding New Tools

1. Create tool function in `app/agents/tools.py`:
```python
def new_tool(param: str) -> str:
    """Tool description"""
    try:
        # Tool implementation
        return result
    except Exception as e:
        logger.error(f"Error in new_tool: {e}")
        return f"Error: {str(e)}"
```

2. Register tool in `AVAILABLE_TOOLS` dictionary

3. Update agent to use the new tool

#### Modifying Agent Behavior

1. Edit `app/agents/simple_agent.py`
2. Update the system prompt in `_get_system_prompt()`
3. Modify the graph structure in `_build_graph()`
4. Test changes locally before deployment

### Configuration Management

#### Environment-Specific Configs

Create multiple environment files:
- `.env.development`
- `.env.staging`
- `.env.production`

Load appropriate config:
```bash
# Development
cp .env.development .env

# Staging
cp .env.staging .env
```

#### Parameter Store Integration

For production-like testing with Parameter Store:

```bash
# Set USE_PARAMETER_STORE=true in .env
# Ensure AWS credentials are configured
# Parameters should exist in Parameter Store
```

## Common Development Issues

### Issue: Import Errors
```
ModuleNotFoundError: No module named 'app'
```

**Solution**: Run from project root and ensure PYTHONPATH is set:
```bash
export PYTHONPATH="${PYTHONPATH}:$(pwd)"
```

### Issue: OpenAI API Key Not Found
```
Error: OpenAI API key not found
```

**Solution**: Set the environment variable:
```bash
export OPENAI_API_KEY="your-key-here"
# or add to .env file
```

### Issue: Port Already in Use
```
Error: Port 8000 is already in use
```

**Solution**: Kill existing processes or use different port:
```bash
# Find process using port 8000
lsof -i :8000

# Kill process
kill -9 <PID>

# Or use different port
uvicorn app.main:app --port 8001
```

### Issue: Docker Build Failures
```
Error: Docker build failed
```

**Solutions**:
1. Check Docker is running
2. Clear Docker cache: `docker system prune`
3. Check Dockerfile syntax
4. Verify base image availability

## Performance Optimization

### Local Performance Tips

1. **Use Python Virtual Environment**: Isolates dependencies
2. **Enable Hot Reload**: For faster development cycle
3. **Optimize Docker Layers**: Cache dependencies separately from code
4. **Use Local Caching**: Cache LLM responses for development

### Memory Management

Monitor memory usage during development:
```bash
# Monitor Python process memory
ps aux | grep python

# Monitor Docker container memory
docker stats

# Use memory profilers
pip install memory-profiler
python -m memory_profiler app/main.py
```

## Database Development (Optional)

If adding database functionality:

### SQLite for Development
```python
# In config.py
DATABASE_URL = "sqlite:///./development.db"
```

### PostgreSQL with Docker
```yaml
# Add to docker-compose.yml
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: langgraph_dev
      POSTGRES_USER: developer
      POSTGRES_PASSWORD: devpass
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

## Integration Development

### Adding External APIs

1. Add API credentials to environment variables
2. Create service modules in `app/services/`
3. Add error handling and retry logic
4. Test with mock responses during development

### Webhook Development

For testing webhooks locally:

```bash
# Use ngrok for local tunneling
brew install ngrok
ngrok http 8000

# Test webhook with ngrok URL
curl -X POST "https://your-ngrok-url.ngrok.io/webhook" \
     -H "Content-Type: application/json" \
     -d '{"test": "data"}'
```

## Deployment Testing

### Pre-deployment Checklist

1. **Environment Variables**: All required variables set
2. **Dependencies**: requirements.txt up to date
3. **Docker Build**: Image builds successfully
4. **Health Checks**: All endpoints respond correctly
5. **Error Handling**: Graceful error responses
6. **Logging**: Appropriate log levels and messages

### Local AWS Testing

Test AWS integrations locally:

```bash
# Use LocalStack for AWS services
pip install localstack
localstack start

# Configure AWS CLI for LocalStack
aws configure set endpoint-url http://localhost:4566
```

## Next Steps

1. **Implement Tests**: Add unit and integration tests
2. **Add Monitoring**: Implement application metrics
3. **Enhance Logging**: Add structured logging with correlation IDs
4. **Security**: Add input validation and rate limiting
5. **Documentation**: Add API documentation and code comments

## Resources

- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [LangGraph Documentation](https://python.langchain.com/docs/langgraph)
- [Docker Documentation](https://docs.docker.com/)
- [Python Best Practices](https://python.org/dev/peps/)
