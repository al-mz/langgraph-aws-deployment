"""
FastAPI application for LangGraph agent deployment
"""

import sys
import os
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel
import logging
import uvicorn
from typing import Dict, Any, Optional, AsyncGenerator
import json

# Add the agent source directory to Python path
agent_src_path = Path(__file__).parent / "agent" / "src"
sys.path.insert(0, str(agent_src_path))

from app.config import settings
from agent.graph import graph, State

# Configure logging
logging.basicConfig(
    level=getattr(logging, settings.log_level.upper()),
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="LangGraph Agent API",
    description="Production-ready LangGraph agent deployment on AWS",
    version="1.0.0",
    docs_url="/docs" if settings.environment != "production" else None,
    redoc_url="/redoc" if settings.environment != "production" else None,
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Graph wrapper for compatibility
class GraphAgent:
    """Wrapper around the LangGraph graph to maintain API compatibility"""
    
    def __init__(self):
        self.graph = graph
        self.sessions = {}
    
    async def process_message(self, message: str, session_id: str = None, context: Dict = None):
        """Process message through the graph"""
        import uuid
        from datetime import datetime
        
        if not session_id:
            session_id = str(uuid.uuid4())
        
        # Create state
        state = State(changeme=message)
        
        # Create config
        config = {
            "configurable": {
                "my_configurable_param": context.get("config", "default") if context else "default"
            }
        }
        
        # Run graph
        result = await self.graph.ainvoke(state, config=config)
        
        return {
            "message": result["changeme"],
            "session_id": session_id,
            "metadata": {
                "timestamp": datetime.now().isoformat(),
                "config": config["configurable"]
            }
        }
    
    async def stream_message(self, message: str, session_id: str = None, context: Dict = None):
        """Stream message processing through the graph"""
        import uuid
        from datetime import datetime
        
        if not session_id:
            session_id = str(uuid.uuid4())
        
        # Create state
        state = State(changeme=message)
        
        # Create config
        config = {
            "configurable": {
                "my_configurable_param": context.get("config", "streaming") if context else "streaming"
            }
        }
        
        # Stream graph execution
        async for chunk in self.graph.astream(state, config=config):
            yield {
                "type": "chunk",
                "data": chunk,
                "session_id": session_id,
                "timestamp": datetime.now().isoformat()
            }
        
        # Final message
        yield {
            "type": "complete",
            "session_id": session_id,
            "timestamp": datetime.now().isoformat()
        }

    async def reset_session(self, session_id: str):
        """Reset session (placeholder for compatibility)"""
        pass
    
    def get_capabilities(self):
        """Get capabilities"""
        return ["LangGraph processing", "Configurable parameters", "State management"]
    
    def get_available_tools(self):
        """Get available tools"""
        return ["call_model"]

# Initialize agent
agent = GraphAgent()

# Request/Response models
class AgentRequest(BaseModel):
    message: str
    session_id: Optional[str] = None
    context: Optional[Dict[str, Any]] = None

class AgentResponse(BaseModel):
    response: str
    session_id: str
    metadata: Optional[Dict[str, Any]] = None

class HealthResponse(BaseModel):
    status: str
    version: str
    environment: str

@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint for load balancer"""
    return HealthResponse(
        status="healthy",
        version="1.0.0",
        environment=settings.environment
    )

@app.post("/chat", response_model=AgentResponse)
async def chat_with_agent(request: AgentRequest):
    """
    Chat with the LangGraph agent
    """
    try:
        logger.info(f"Processing request for session: {request.session_id}")
        
        # Process the message with the agent
        response = await agent.process_message(
            message=request.message,
            session_id=request.session_id,
            context=request.context or {}
        )
        
        return AgentResponse(
            response=response["message"],
            session_id=response["session_id"],
            metadata=response.get("metadata", {})
        )
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")

@app.post("/chat/stream")
async def stream_chat_with_agent(request: AgentRequest):
    """
    Stream chat with the LangGraph agent
    """
    try:
        logger.info(f"Starting streaming for session: {request.session_id}")
        
        async def generate_stream():
            async for chunk in agent.stream_message(
                message=request.message,
                session_id=request.session_id,
                context=request.context or {}
            ):
                yield f"data: {json.dumps(chunk)}\n\n"
            
            yield "data: [DONE]\n\n"
        
        return StreamingResponse(
            generate_stream(),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
            }
        )
        
    except Exception as e:
        logger.error(f"Error streaming request: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")

@app.get("/agent/info")
async def get_agent_info():
    """Get information about the agent"""
    return {
        "agent_type": "SimpleAgent",
        "capabilities": agent.get_capabilities(),
        "tools": agent.get_available_tools()
    }

@app.post("/agent/reset/{session_id}")
async def reset_session(session_id: str):
    """Reset a specific agent session"""
    try:
        await agent.reset_session(session_id)
        return {"message": f"Session {session_id} reset successfully"}
    except Exception as e:
        logger.error(f"Error resetting session {session_id}: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to reset session")

@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    """Global exception handler"""
    logger.error(f"Unhandled exception: {str(exc)}")
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"}
    )

if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=settings.environment == "development"
    )
