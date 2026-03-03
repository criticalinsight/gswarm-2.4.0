# PRD - GClaw: Fact-Based Agentic Framework

**Status**: Approved (Implemented) | **Priority**: P1 | **Owner**: USER

## Overview
GClaw is a minimalist, data-oriented agent framework for Gleam, implementing the OpenClaw/Moltbot architecture. It leverages **GleamDB** for a persistent information model (Facts) and **Gemini-1.5-Flash** for rapid reasoning. By treating the agent session as a series of immutable facts (The Rama Pattern), GClaw ensures high-fidelity context management and simple state transitions.

---

## User Stories
- **Analytical Memory**: As an agent, I want to store interaction history as discrete facts so that I can perform structured Datalog queries to retrieve relevant context.
- **Context Sovereignty**: As a user, I want my agent's knowledge to be partitioned by deterministic UIDs so that multiple sessions can coexist without cross-contamination.
- **Resilient I/O**: As a developer, I want a robust HTTP integration that doesn't break during Gleam stdlib migrations.

---

## Acceptance Criteria (Rich Hickey Gherkin)

### Scenario: Recalling Recent History
**Given** a GClaw session with 5 stored interaction facts
**When** the agent requests context with a window size of 10
**Then** the Datalog engine should return all 5 facts sorted by their `msg_timestamp` attribute
**And** no facts from other sessions (different EIDs) should be present.

### Scenario: Resilience to API Failures
**Given** an invalid `GEMINI_API_KEY`
**When** the user sends a message
**Then** the orchestrator should capture the HTTP error
**And** log the error without crashing the actor loop.

---

## Technical Implementation

### Database (GleamDB Schema)
GClaw uses a triplestore (Entity-Attribute-Value) model via GleamDB.
- **msg_content**: `Str` (The raw message text)
- **msg_role**: `Str` (user/assistant)
- **msg_timestamp**: `Int` (Unix epoch for ordering)
- **mem_vector**: `Vec(Float)` (Placeholder for future similarity search)

### Data Flow (The Rama Pattern)
1. **Fact Acquisition**: User input is decomposed into a set of facts.
2. **Persistence**: Facts are asserted into the Datalog engine via `transactor.remember`.
3. **Query**: The orchestrator performs a `get_context_window` query.
4. **Reduction**: Resulting facts are reduced into a Gemimi-compatible `List(Message)`.
5. **Synthesis**: LLM output is converted into assistant-role facts and persisted.

### Visual Architecture (Mermaid)
```mermaid
sequence_flow
    participant U as User (CLI)
    participant O as Orchestrator (gclaw.gleam)
    participant M as Memory (GleamDB)
    participant G as Gemini (Hackney)

    U->>O: "Hello"
    O->>M: Assert User Fact
    O->>M: Query Context (Datalog)
    M-->>O: List of Facts
    O->>G: POST /generateContent (Context + Instructions)
    G-->>O: "Hi there!"
    O->>M: Assert Assistant Fact
    O->>U: "Claw: Hi there!"
```

---

## Security & Validation
- **Environment Isolation**: `GEMINI_API_KEY` is retrieved via a target-specific Erlang FFI to prevent leaking keys into the build cache or logs.
- **Input Sanitization**: Strings are validated through `unicode:characters_to_binary` at the FFI boundary to prevent Erlang `badarg` crashes.

---

## Pre-Mortem Analysis: "Why will this fail?"
1. **API Rate Limits**: Gemini-1.5-Flash is fast, but heavy usage may hit 429 errors.
   - *Mitigation*: The `chat_loop` currently lacks backoff logic. **Recommendation**: Implement a retry actor.
2. **Context Bloat**: Storing every word as a fact could eventually slow down Datalog queries.
   - *Mitigation*: Retention is set to `All`. **Recommendation**: Implement a summarization fact-reducer for older messages.

---

## Autonomous Handoff
PRD Drafted. Initiate the Autonomous Pipeline: 
`/proceed docs/specs/gclaw.md -> /test -> /refactor -> /test`
