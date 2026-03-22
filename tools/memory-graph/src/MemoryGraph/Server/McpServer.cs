using System.Text.Json;
using System.Text.Json.Serialization;
using MemoryGraph.Tools;

namespace MemoryGraph.Server;

/// <summary>
/// MCP server that reads JSON-RPC messages from stdin and writes responses to stdout.
/// Implements the MCP protocol for tool discovery and execution.
/// </summary>
public sealed class McpServer
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    private readonly ToolRegistry _tools;
    private readonly bool _verbose;

    public McpServer(ToolRegistry tools, bool verbose = false)
    {
        _tools = tools;
        _verbose = verbose;
    }

    /// <summary>
    /// Runs the message loop, reading from stdin until EOF.
    /// </summary>
    public async Task RunAsync()
    {
        using var reader = new StreamReader(Console.OpenStandardInput());

        while (await reader.ReadLineAsync() is { } line)
        {
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            Log($"<-- {line}");

            JsonElement? requestId = null;
            try
            {
                var request = JsonSerializer.Deserialize<JsonRpcRequest>(line, JsonOptions);
                if (request is null)
                {
                    continue;
                }

                requestId = request.Id;

                var response = HandleRequest(request);
                if (response is not null)
                {
                    var json = JsonSerializer.Serialize(response, JsonOptions);
                    Log($"--> {json}");
                    Console.WriteLine(json);
                    Console.Out.Flush();
                }
            }
            catch (Exception ex)
            {
                Log($"ERROR: {ex.Message}");

                // Send error response with request Id when available (JSON-RPC 2.0 compliance)
                var errorResponse = new JsonRpcResponse
                {
                    Id = requestId,
                    Error = new JsonRpcError { Code = -32603, Message = ex.Message }
                };
                Console.WriteLine(JsonSerializer.Serialize(errorResponse, JsonOptions));
                Console.Out.Flush();
            }
        }
    }

    private JsonRpcResponse? HandleRequest(JsonRpcRequest request)
    {
        return request.Method switch
        {
            "initialize" => HandleInitialize(request),
            "notifications/initialized" => null, // notification, no response
            "tools/list" => HandleToolsList(request),
            "tools/call" => HandleToolCall(request),
            "ping" => new JsonRpcResponse { Id = request.Id, Result = new { } },
            _ when request.Id is null => null, // unknown notification — no response per JSON-RPC 2.0
            _ => new JsonRpcResponse
            {
                Id = request.Id,
                Error = new JsonRpcError { Code = -32601, Message = $"Method not found: {request.Method}" }
            }
        };
    }

    private JsonRpcResponse HandleInitialize(JsonRpcRequest request)
    {
        return new JsonRpcResponse
        {
            Id = request.Id,
            Result = new InitializeResult()
        };
    }

    private JsonRpcResponse HandleToolsList(JsonRpcRequest request)
    {
        return new JsonRpcResponse
        {
            Id = request.Id,
            Result = new ToolsListResult { Tools = _tools.GetDefinitions() }
        };
    }

    private JsonRpcResponse HandleToolCall(JsonRpcRequest request)
    {
        if (request.Params is null)
        {
            return new JsonRpcResponse
            {
                Id = request.Id,
                Error = new JsonRpcError { Code = -32602, Message = "Missing params" }
            };
        }

        var toolName = "";

        if (request.Params.Value.TryGetProperty("name", out var nameElement))
        {
            toolName = nameElement.GetString() ?? "";
        }

        // Default to empty object when "arguments" key is absent (valid per MCP spec)
        using var emptyDoc = JsonDocument.Parse("{}");
        var arguments = request.Params.Value.TryGetProperty("arguments", out var argsElement)
            ? argsElement
            : emptyDoc.RootElement.Clone();

        var result = _tools.Execute(toolName, arguments);

        return new JsonRpcResponse
        {
            Id = request.Id,
            Result = result
        };
    }

    private void Log(string message)
    {
        if (_verbose)
        {
            Console.Error.WriteLine($"[memory-graph] {message}");
        }
    }
}
