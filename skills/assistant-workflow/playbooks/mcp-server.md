# MCP Server

**Architecture:** Handler-per-tool + shared services

## Folder structure (C#)
```
src/
  McpServer/
    Tools/                # One class per tool
    Services/             # Shared services
    Models/               # Request/response DTOs
    Program.cs            # Host builder, DI, tool registration
tests/
  McpServer.Tests/
```

## Folder structure (TypeScript)
```
src/
  tools/                  # One file per tool
  services/
  types/
  index.ts
tests/
```

## Typical Discovery Q&A
```
1. Runtime?
   a) C# with ModelContextProtocol.Server (recommended for .NET)
   b) TypeScript with @modelcontextprotocol/sdk
   c) Python with FastMCP
2. Transport?
   a) stdio (local)  b) SSE (remote)  c) Both
3. Tools to expose? (list each with purpose)
4. Persistent state?
   a) No — stateless (recommended)  b) Yes — describe
5. Auth?
   a) None (local)  b) API key  c) OAuth
```

## Architecture rules (Plan phase)
- One tool = one class/function with clear input/output schema
- Tools must not depend on each other directly
- Shared logic in services, injected via DI
- Tool descriptions clear enough for an LLM to choose when to use them
- Structured error responses, not raw exceptions
- Document all side effects in tool descriptions
- No secrets in tool code — use configuration

## Design rules
N/A — no UI.

## Build/test
```
# C#
dotnet build
dotnet test

# TypeScript
npm run build
npm test
```
