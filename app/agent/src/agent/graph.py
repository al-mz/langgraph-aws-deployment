"""LangGraph agent with OpenAI integration.

A complete LangGraph implementation that connects to OpenAI's API.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any, Dict, TypedDict

from langchain_core.runnables import RunnableConfig
from langchain_openai import ChatOpenAI
from langchain_core.messages import HumanMessage, SystemMessage
from langgraph.graph import StateGraph, END


class Configuration(TypedDict):
    """Configurable parameters for the agent.

    Set these when creating assistants OR when invoking the graph.
    See: https://langchain-ai.github.io/langgraph/cloud/how-tos/configuration_cloud/
    """

    my_configurable_param: str


@dataclass
class State:
    """Input state for the agent.

    Defines the initial structure of incoming data.
    See: https://langchain-ai.github.io/langgraph/concepts/low_level/#state
    """

    changeme: str = "example"


async def call_model(state: State, config: RunnableConfig) -> Dict[str, Any]:
    """Process input using OpenAI and return the response.

    Uses the configured OpenAI model to generate responses based on user input.
    """
    # Get configuration
    configuration = config.get("configurable", {})
    model_type = configuration.get("my_configurable_param", "default")
    
    # Initialize the OpenAI model
    llm = ChatOpenAI(
        model="gpt-4o-mini",  # Use a specific model for better performance
        temperature=0.7,
        api_key=os.getenv("OPENAI_API_KEY")
    )
    
    # Create system message based on configuration
    system_prompts = {
        "default": "You are a helpful AI assistant.",
        "friendly": "You are a friendly and enthusiastic AI assistant who loves helping people.",
        "detailed": "You are a detailed AI assistant who provides comprehensive and thorough responses.",
        "helpful": "You are a helpful AI assistant focused on providing practical solutions.",
        "interactive": "You are an interactive AI assistant who engages in natural conversation.",
        "streaming": "You are an AI assistant that provides responses in a conversational manner."
    }
    
    system_message = system_prompts.get(model_type, system_prompts["default"])
    
    # Create messages
    messages = [
        SystemMessage(content=system_message),
        HumanMessage(content=state.changeme)
    ]
    
    try:
        # Call OpenAI
        response = await llm.ainvoke(messages)
        return {"changeme": response.content}
    
    except Exception as e:
        # Fallback response if OpenAI fails
        return {
            "changeme": f"I apologize, but I'm having trouble connecting to the AI service right now. "
                       f"Error: {str(e)}. Please make sure your OPENAI_API_KEY is set correctly."
        }


# Define the graph
workflow = StateGraph(State, config_schema=Configuration)
workflow.add_node("call_model", call_model)
workflow.add_edge("__start__", "call_model")
workflow.add_edge("call_model", END)

# Compile the graph
graph = workflow.compile()
