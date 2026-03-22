using System.Text.Json;
using System.Text.Json.Serialization;

namespace MemoryGraph.Server;

/// <summary>
/// MCP protocol types for JSON-RPC communication over stdio.
/// </summary>

// ── JSON-RPC base types ────────────────────────────────────────

public sealed class JsonRpcRequest
{
    [JsonPropertyName("jsonrpc")]
    public string JsonRpc { get; set; } = "2.0";

    [JsonPropertyName("id")]
    public JsonElement? Id { get; set; }

    [JsonPropertyName("method")]
    public string Method { get; set; } = "";

    [JsonPropertyName("params")]
    public JsonElement? Params { get; set; }
}

public sealed class JsonRpcResponse
{
    [JsonPropertyName("jsonrpc")]
    public string JsonRpc { get; set; } = "2.0";

    [JsonPropertyName("id")]
    public JsonElement? Id { get; set; }

    [JsonPropertyName("result")]
    public object? Result { get; set; }

    [JsonPropertyName("error")]
    public JsonRpcError? Error { get; set; }
}

public sealed class JsonRpcError
{
    [JsonPropertyName("code")]
    public int Code { get; set; }

    [JsonPropertyName("message")]
    public string Message { get; set; } = "";
}

// ── MCP Initialize ─────────────────────────────────────────────

public sealed class InitializeResult
{
    [JsonPropertyName("protocolVersion")]
    public string ProtocolVersion { get; set; } = "2024-11-05";

    [JsonPropertyName("capabilities")]
    public ServerCapabilities Capabilities { get; set; } = new();

    [JsonPropertyName("serverInfo")]
    public ServerInfo ServerInfo { get; set; } = new();
}

public sealed class ServerCapabilities
{
    [JsonPropertyName("tools")]
    public ToolsCapability Tools { get; set; } = new();
}

public sealed class ToolsCapability
{
    [JsonPropertyName("listChanged")]
    public bool ListChanged { get; set; } = false;
}

public sealed class ServerInfo
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = "memory-graph";

    [JsonPropertyName("version")]
    public string Version { get; set; } = "1.0.0";
}

// ── MCP Tools ──────────────────────────────────────────────────

public sealed class ToolDefinition
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("description")]
    public string Description { get; set; } = "";

    [JsonPropertyName("inputSchema")]
    public JsonElement InputSchema { get; set; }
}

public sealed class ToolsListResult
{
    [JsonPropertyName("tools")]
    public List<ToolDefinition> Tools { get; set; } = [];
}

public sealed class ToolCallResult
{
    [JsonPropertyName("content")]
    public List<ToolContent> Content { get; set; } = [];

    [JsonPropertyName("isError")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)]
    public bool IsError { get; set; }
}

public sealed class ToolContent
{
    [JsonPropertyName("type")]
    public string Type { get; set; } = "text";

    [JsonPropertyName("text")]
    public string Text { get; set; } = "";
}
