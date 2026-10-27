"""Refresh assets through the running editor without changing its view/layout."""
import asyncio
from pathlib import Path
from fastmcp import Client
from fastmcp.client.transports import StdioTransport

async def main():
    bridge = Path.home() / '.local/bin/godot-ai.exe'
    transport = StdioTransport(command=str(bridge), args=['attach', '--disable-telemetry'])
    async with Client(transport, timeout=120) as client:
        await client.call_tool('session_activate', {'session_id': Path(__file__).resolve().parents[1].as_posix()})
        result = await client.call_tool('filesystem_manage', {'op': 'scan'})
        assert result.structured_content and result.structured_content.get('scan_completed'), result
        print('Running Godot editor refreshed; editor window and view preserved')

asyncio.run(main())
