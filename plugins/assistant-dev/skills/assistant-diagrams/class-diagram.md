# Class Diagram

## Protocol

### Step 1: Identify Scope

Don't diagram every class. Focus on:
- A specific feature's type hierarchy
- Interface and implementation relationships
- Design pattern structure
- The types the user is asking about

### Step 2: Extract Type Information

For each relevant type:
- Class/interface/abstract/enum
- Key properties and methods (not all — just the important ones)
- Inheritance relationships
- Interface implementations
- Composition and aggregation

### Step 3: Generate

```mermaid
classDiagram
    class IRepository~T~ {
        <<interface>>
        +GetById(id) T
        +GetAll() List~T~
        +Add(entity) void
        +Update(entity) void
        +Delete(id) void
    }

    class UserRepository {
        -DbContext _context
        +GetById(id) User
        +GetAll() List~User~
        +GetByEmail(email) User
    }

    class IUserService {
        <<interface>>
        +Register(dto) Result
        +GetProfile(id) UserProfile
    }

    class UserService {
        -IRepository~User~ _repo
        -IValidator _validator
        +Register(dto) Result
        +GetProfile(id) UserProfile
    }

    IRepository~T~ <|.. UserRepository
    IUserService <|.. UserService
    UserService --> IRepository~T~
    UserService --> IValidator
```

### Guidelines

- Use `<<interface>>` and `<<abstract>>` stereotypes
- Show only 3-5 key members per type
- Solid arrow with triangle for inheritance
- Dashed arrow for implementation
- Solid arrow for composition/dependency
- Max 10-12 types per diagram
