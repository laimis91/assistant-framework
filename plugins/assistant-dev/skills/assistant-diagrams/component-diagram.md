# Component Diagram

## Protocol

### Step 1: Identify Components

Components are deployable or logically independent units:
- .NET projects in a solution
- npm packages in a monorepo
- Microservices
- Shared libraries
- External systems

### Step 2: Map Dependencies

For each component:
- What it depends on (project references, package references)
- What depends on it
- Interface boundaries (what's exposed vs. internal)

### Step 3: Generate

```mermaid
graph LR
    subgraph Solution
        API[API Project]
        App[Application Layer]
        Domain[Domain Layer]
        Infra[Infrastructure]
        Tests[Test Projects]
    end

    subgraph External
        DB[(Database)]
        Queue[[Message Queue]]
        ExtAPI[[External API]]
    end

    API --> App
    API --> Domain
    App --> Domain
    Infra --> Domain
    Infra --> App
    Infra --> DB
    Infra --> Queue
    Infra --> ExtAPI
    Tests -.-> API
    Tests -.-> App
    Tests -.-> Domain
```

### Guidelines

- Solid arrows for runtime dependencies
- Dashed arrows for test/dev dependencies
- Group by deployment boundary with `subgraph`
- Show dependency direction (arrow points TO the dependency)
- Highlight violations (e.g., Domain depending on Infrastructure) with red styling
