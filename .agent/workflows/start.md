---
description: Initialize the Amkabot engine and local development environment
---

# Start Workflow (Amkabot)

Quickly bring the system online for development or verification.

## 1. Dependencies
Ensure Erlang 26+ and Gleam 1.14+ are installed.

## 2. Database (Optional for UI)
- The system is **Local-First Resilient**. 
- If Postgres is desired: `brew services start postgresql`.
- If not: The system will fallback to in-memory mirroring.

## 3. Execution
// turbo
```bash
gleam run
```

## 4. Verification
- Access the web UI at `http://localhost:8000`.
- Verify the `server.log` for successful ingestion polling.
