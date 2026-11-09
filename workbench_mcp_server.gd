@tool
extends Node

const MCP_PORT = 6005
var _server := TCPServer.new()
var _timer := Timer.new()

func _ready():
    print("Starting Godot AI Workbench MCP server on port ", MCP_PORT)
    var error = _server.listen(MCP_PORT)
    if error != OK:
        print("Failed to start MCP server: ", error)
        set_process(false)
        return
    
    print("MCP server listening on port ", MCP_PORT)
    
    # Setup timer
    _timer.wait_time = 0.1
    _timer.timeout.connect(_check_connections)
    add_child(_timer)
    _timer.start()

func _check_connections():
    if _server.is_listening():
        var client = _server.take_connection()
        if client != null:
            print("Client connected")
            # Send MCP greeting
            var greeting = JSON.stringify({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {"tools": {}},
                    "clientInfo": {"name": "godot-ai-workbench", "version": "0.1.0"}
                }
            }) + "\n"
            client.put_data(greeting.to_utf8())
            client.disconnect_from_host()

func _exit_tree():
    if _server.is_listening():
        _server.stop()
