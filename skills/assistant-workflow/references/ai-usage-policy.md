# AI Usage Policy

Rules for safe and effective AI-assisted development. These apply throughout all workflow phases.

## Data rules — what goes into prompts

**Never include:**
- Secrets, API keys, tokens, passwords, or credentials
- Production database connection strings
- PII (personally identifiable information) unless the task requires it and the data is anonymized/synthetic
- Customer data, financial records, or health information
- Internal security configurations or vulnerability details
- License keys or proprietary algorithms not owned by the user

**Safe to include:**
- Code from the repo being worked on
- Architecture descriptions and design documents
- Error messages and stack traces (redact any embedded credentials)
- Configuration structure (without actual secret values)
- Public API documentation and open-source references
- Test data (use synthetic/mock data, not production data)

**When uncertain:** Ask the user before including potentially sensitive content.

## AI output validation rules

### Code
- All AI-generated code must be human-reviewed before merge
- Review for correctness, not just "does it compile"
- Verify the AI didn't introduce unnecessary dependencies
- Check that error handling covers real failure modes, not just happy path
- Verify no hardcoded values that should be configuration
- Run the code — don't trust it works just because it looks right

### Tests
- AI-generated tests must test behaviour, not implementation details
- Tests must be able to fail (verify by breaking the code and confirming the test catches it)
- Test names must clearly describe what they verify
- Avoid AI generating tests that simply assert the current output is correct (tautological tests)
- Human must define expected behaviour; AI can scaffold the test structure
- Prefer Arrange-Act-Assert pattern for clarity

### Documentation
- AI-generated docs must be verified against actual code
- Check that API signatures, parameter names, and return types match reality
- Verify code examples actually compile and run
- Don't blindly trust AI-generated changelogs — compare against actual diff

### Plans and architecture
- AI recommendations must be justified with reasoning, not just stated
- Verify AI's claims about existing codebase against actual code (rg, git log)
- If the AI says "this pattern is already used in the project," confirm it

## Uncertainty and hallucination handling

**The AI must:**
- Flag uncertainty explicitly: "I'm not sure about X — please verify"
- Never present guesses as facts
- Say "I don't know" rather than fabricate an answer
- Cite specific file paths when referencing existing code
- Admit when it can't verify something (e.g., runtime behaviour, external service responses)

**The human should:**
- Be skeptical of confident-sounding AI claims about unfamiliar codebases
- Verify AI's understanding of business rules against product requirements
- Question AI recommendations that seem overly complex or that introduce new patterns not in the codebase

## Tool and agent permissions

When AI has tool access (Claude Code, Codex CLI, MCP servers):

**Allowed without asking:**
- Read files, search code (rg, grep), browse directories
- Run build commands (dotnet build, npm run build, pio run)
- Run test commands (dotnet test, npm test, pio test)
- Git status, log, diff, blame (read-only git operations)

**Requires user confirmation:**
- Writing or modifying files
- Git commits, branch creation, pushes
- Installing packages or dependencies
- Running scripts that modify system state
- Accessing external APIs or services

**Never allowed:**
- Accessing production systems or databases
- Modifying CI/CD pipeline configuration without review
- Deploying to any environment
- Modifying access controls or permissions
- Sending emails, messages, or notifications on behalf of the user
