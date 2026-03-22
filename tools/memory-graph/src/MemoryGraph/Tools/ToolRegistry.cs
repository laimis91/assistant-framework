using System.Text.Json;
using MemoryGraph.Server;

namespace MemoryGraph.Tools;

/// <summary>
/// Registry for all MCP tools. Routes tool calls to implementations.
/// </summary>
public sealed class ToolRegistry
{
    private readonly Dictionary<string, IMemoryTool> _tools = new(StringComparer.OrdinalIgnoreCase);

    public void Register(IMemoryTool tool)
    {
        _tools[tool.Name] = tool;
    }

    public List<ToolDefinition> GetDefinitions()
    {
        return _tools.Values.Select(t => t.GetDefinition()).ToList();
    }

    public ToolCallResult Execute(string toolName, JsonElement arguments)
    {
        if (!_tools.TryGetValue(toolName, out var tool))
        {
            return new ToolCallResult
            {
                Content = [new ToolContent { Text = $"Unknown tool: {toolName}" }],
                IsError = true
            };
        }

        try
        {
            return tool.Execute(arguments);
        }
        catch (Exception ex)
        {
            return new ToolCallResult
            {
                Content = [new ToolContent { Text = $"Error executing {toolName}: {ex.Message}" }],
                IsError = true
            };
        }
    }
}

/// <summary>
/// Interface for all memory graph MCP tools.
/// </summary>
public interface IMemoryTool
{
    string Name { get; }
    ToolDefinition GetDefinition();
    ToolCallResult Execute(JsonElement arguments);
}
