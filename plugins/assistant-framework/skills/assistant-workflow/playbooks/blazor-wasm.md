# Blazor WebAssembly

**Architecture:** Clean Architecture + component-based UI with MVVM-like separation

## Folder structure
```
src/
  Domain/
  Application/
  Infrastructure/        # HttpClient-based service implementations
  Client/                # Blazor WASM project
    Components/
      Shared/            # Layout, NavMenu, reusable components
      Features/          # Feature-based component folders
    Services/
    wwwroot/
  Server/ (if hosted)
tests/
  Domain.Tests/
  Application.Tests/
  Client.Tests/          # bUnit component tests
```

## Typical Discovery Q&A
```
1. Hosting model?
   a) Standalone WASM (separate API)
   b) ASP.NET Hosted (Server + Client)
   c) Blazor Hybrid (MAUI shell)
2. State management?
   a) Cascading parameters + service injection (recommended)
   b) Fluxor (Redux-like, for complex state)
   c) Simple state containers
3. Component library?
   a) Custom components  b) MudBlazor  c) Radzen  d) Other
4. Auth?
   a) OIDC / Identity  b) JWT  c) None for now
```

## Architecture rules (Plan phase)
- Clean Architecture layers same as .NET Web API
- CSS isolation (.razor.css) per component
- Prefer @bind and EventCallback over JS interop
- Each feature component: Default, Loading, Empty, Error states
- Use `<ErrorBoundary>` around feature components
- HttpClient calls through service interfaces, not direct in components
- No business logic in components — delegate to services

## Design rules (Design phase)
- CSS variables in wwwroot/css/app.css for theming
- Create Shared/ component for each reusable element
- Component states: Default, Loading, Empty, Error, Disabled
- Responsive breakpoints: 375px, 768px, 1280px
- Accessibility: semantic HTML, ARIA labels on custom components
- Test with "Slow 3G" throttling for loading states

## Build/test
```
dotnet build
dotnet test
# Browser console check for WASM errors after publish
```
