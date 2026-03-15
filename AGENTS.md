<!-- EFCTL_INSTRUCTIONS_START -->
# Agent Constitution

This document defines the core principles and operational constraints for any AI Agent working on this repository.

## 1. Test-First Development
All features and bug fixes must follow a test-driven approach.

## 2. Testing Pyramid Adherence
- **Unit Tests:** High volume, isolation.
- **Integration Tests:** Interaction between modules.
- **E2E Tests:** Full user flows.

## 3. Clean Code & Quality Gates
- Write clean, maintainable, and idiomatic Go code.
- Always run pre-commit hooks.

## 4. Security-First
Prioritize security in every change. Avoid hardcoding credentials.

## 5. Independent Operation
The Agent is authorized to operate independently.

## 6. Environmental Isolation
- Use ./tmp for temporary files.
- Do not write to system-level directories.

## 7. Context-Mode Routing
- Prefer context-mode MCP tools for large analysis.

## 8. Development Cheat Sheet

Quick reference for common efctl operations:

- **Initialize configuration**: efctl init (or efctl init --ai [agent])
- **Environment Lifecycle**:
  - Up: efctl env up
  - Down: efctl env down
- **Status Check**: efctl env status
- **Deploy Extension**: efctl env extension publish [contract-path] (path defaults to ./my-extension)
- **Query World**: efctl world query [object_id] (queries the Sui GraphQL RPC)
<!-- EFCTL_INSTRUCTIONS_END -->
