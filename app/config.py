"""
Application configuration management
"""

import os
from typing import List
from pydantic_settings import BaseSettings
from pydantic import Field

class Settings(BaseSettings):
    """Application settings with environment variable support"""
    
    # Environment
    environment: str = Field(default="development", env="ENVIRONMENT")
    log_level: str = Field(default="INFO", env="LOG_LEVEL")
    
    # API Configuration
    api_host: str = Field(default="0.0.0.0", env="API_HOST")
    api_port: int = Field(default=8000, env="API_PORT")
    allowed_origins: List[str] = Field(
        default=["*"], 
        env="ALLOWED_ORIGINS",
        description="Comma-separated list of allowed origins"
    )
    
    # OpenAI Configuration
    openai_api_key: str = Field(env="OPENAI_API_KEY")
    openai_model: str = Field(default="gpt-4", env="OPENAI_MODEL")
    
    # AWS Configuration
    aws_region: str = Field(default="us-east-1", env="AWS_DEFAULT_REGION")
    aws_access_key_id: str = Field(default="", env="AWS_ACCESS_KEY_ID")
    aws_secret_access_key: str = Field(default="", env="AWS_SECRET_ACCESS_KEY")
    
    # Parameter Store Configuration (for production secrets)
    use_parameter_store: bool = Field(default=False, env="USE_PARAMETER_STORE")
    parameter_store_prefix: str = Field(default="/langgraph/", env="PARAMETER_STORE_PREFIX")
    
    # Agent Configuration
    agent_timeout: int = Field(default=30, env="AGENT_TIMEOUT")
    max_iterations: int = Field(default=10, env="MAX_ITERATIONS")
    
    # Session Configuration
    session_timeout: int = Field(default=3600, env="SESSION_TIMEOUT")  # 1 hour
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False
        
        @classmethod
        def parse_env_var(cls, field_name: str, raw_val: str):
            if field_name == "allowed_origins":
                return [x.strip() for x in raw_val.split(",")]
            return cls.json_loads(raw_val)

# Global settings instance
settings = Settings()

def get_settings() -> Settings:
    """Get application settings"""
    return settings

def load_aws_secrets():
    """Load secrets from AWS Parameter Store in production"""
    if not settings.use_parameter_store:
        return
        
    try:
        import boto3
        
        ssm = boto3.client('ssm', region_name=settings.aws_region)
        
        # Load OpenAI API key from Parameter Store
        if not settings.openai_api_key:
            try:
                response = ssm.get_parameter(
                    Name=f"{settings.parameter_store_prefix}openai-api-key",
                    WithDecryption=True
                )
                settings.openai_api_key = response['Parameter']['Value']
            except Exception as e:
                print(f"Warning: Could not load OpenAI API key from Parameter Store: {e}")
                
    except ImportError:
        print("Warning: boto3 not available, skipping Parameter Store integration")
    except Exception as e:
        print(f"Warning: Error loading secrets from Parameter Store: {e}")

# Load AWS secrets on import in production
if settings.environment == "production":
    load_aws_secrets()
