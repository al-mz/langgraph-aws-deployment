#!/usr/bin/env python3
"""
Interactive chat client for testing your LangGraph agent
"""

import asyncio
import aiohttp
import json
import sys
from datetime import datetime

class ChatClient:
    def __init__(self, base_url="http://localhost:8002"):
        self.base_url = base_url
        self.session_id = f"chat-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    
    async def send_message(self, message, stream=False):
        """Send a message to the agent"""
        endpoint = "/chat/stream" if stream else "/chat"
        
        payload = {
            "message": message,
            "session_id": self.session_id,
            "context": {"config": "interactive"}
        }
        
        async with aiohttp.ClientSession() as session:
            try:
                async with session.post(
                    f"{self.base_url}{endpoint}",
                    json=payload,
                    headers={"Content-Type": "application/json"}
                ) as response:
                    
                    if response.status != 200:
                        print(f"❌ Error: {response.status} - {await response.text()}")
                        return
                    
                    if stream:
                        print("🤖 Agent (streaming):", end=" ")
                        async for line in response.content:
                            if line:
                                line_str = line.decode('utf-8').strip()
                                if line_str.startswith('data: ') and line_str != 'data: [DONE]':
                                    try:
                                        data = json.loads(line_str[6:])
                                        if data.get('type') == 'chunk':
                                            chunk_data = data.get('data', {})
                                            for key, value in chunk_data.items():
                                                if isinstance(value, dict) and 'changeme' in value:
                                                    print(value['changeme'])
                                    except json.JSONDecodeError:
                                        continue
                    else:
                        data = await response.json()
                        print(f"🤖 Agent: {data['response']}")
                        
            except Exception as e:
                print(f"❌ Connection error: {e}")
    
    async def interactive_chat(self):
        """Start interactive chat session"""
        print("🚀 LangGraph Agent Chat Client")
        print("=" * 40)
        print(f"Session ID: {self.session_id}")
        print("Type 'quit' to exit, 'stream:' to send streaming message")
        print("=" * 40)
        
        while True:
            try:
                user_input = input("\n💭 You: ").strip()
                
                if user_input.lower() in ['quit', 'exit', 'q']:
                    print("👋 Goodbye!")
                    break
                
                if not user_input:
                    continue
                
                # Check for streaming mode
                if user_input.startswith('stream:'):
                    message = user_input[7:].strip()
                    if message:
                        await self.send_message(message, stream=True)
                else:
                    await self.send_message(user_input, stream=False)
                
            except KeyboardInterrupt:
                print("\n👋 Chat interrupted. Goodbye!")
                break
            except EOFError:
                print("\n👋 Goodbye!")
                break

async def main():
    """Main function"""
    if len(sys.argv) > 1:
        # Single message mode
        message = " ".join(sys.argv[1:])
        client = ChatClient()
        print(f"💭 You: {message}")
        await client.send_message(message)
    else:
        # Interactive mode
        client = ChatClient()
        await client.interactive_chat()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except Exception as e:
        print(f"❌ Error: {e}")
