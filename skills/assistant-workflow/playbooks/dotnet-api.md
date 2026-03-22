# .NET Web API / Service

**Architecture:** Clean (Onion) — Domain → Application → Infrastructure → API

## Folder structure
```
src/
  Domain/           # Entities, value objects, domain events, interfaces
  Application/      # Use cases, DTOs, validation, handlers
  Infrastructure/   # EF Core, external services, email, file storage
  Api/              # Endpoints, middleware, DI composition root
tests/
  Domain.Tests/
  Application.Tests/
  Infrastructure.Tests/
  Api.IntegrationTests/
```

## Typical Discovery Q&A
```
1. API style?
   a) Minimal API (recommended for .NET 8+)
   b) Controllers
2. Auth?
   a) JWT Bearer  b) Cookie  c) API key  d) None for now
3. Database?
   a) PostgreSQL  b) SQL Server  c) SQLite (dev only)
4. CQRS / MediatR or direct service injection?
   a) MediatR (recommended for complex domains)
   b) Direct service injection (simpler)
```

## Architecture rules (Plan phase)
- Domain: zero package references — no EF Core, no ASP.NET
- Application: references only Domain
- Infrastructure: references Application + Domain
- Api: references all (composition root) but only through interfaces
- All DbContext access in Infrastructure, never in Application
- Entities use Fluent API config, not data annotations
- Microsoft.Extensions.DependencyInjection for DI
- No hardcoded connection strings or secrets — use configuration

## Design rules
N/A — backend only. Frontend projects have their own playbook.

## Build/test
```
dotnet build --no-restore
dotnet test --no-build --verbosity normal
```
