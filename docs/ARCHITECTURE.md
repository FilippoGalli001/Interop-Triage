# Architecture Details

The details behind the [README](../README.md).

- [Native Retries First](#native-retries-first)
- [Governance Rules](#governance-rules)
- [Production Settings](#production-settings)
- [Agent Tools and Prompt Safety](#agent-tools-and-prompt-safety)
- [Knowledge and Operator Memory](#knowledge-and-operator-memory)
- [How Replay Mode Stays Honest](#how-replay-mode-stays-honest)
- [MCP Server](#mcp-server)
- [Dashboard](#dashboard)
- [Measurements](#measurements)
- [Tests](#tests)
- [Plugging It Into Your Own Production](#plugging-it-into-your-own-production)
- [Reviews From the Terminal](#reviews-from-the-terminal)
- [Repository Layout](#repository-layout)

## Native Retries First

1. `Demo.ERP` sets `RetryInterval=5`, `FailureTimeout=15` and `AlertRetryGracePeriod=60`, and both demo operations retry `502` and `504` themselves (`RetryableStatusCodes`). A short blip such as SO-1008 is resolved by the operation: no alert, no LLM call.
2. When an outage lasts longer than `FailureTimeout`, keeping the message in a `PoolSize=1` queue would block every valid message behind it. The operation gives up after 15 seconds and alerts `Ens.Alert`, which frees the queue.
3. `TriageProcess` schedules the resend out of band through `Ens.Alarm`: `OnResponse` wakes the process in the same Visual Trace session and calls `Ens.MessageHeader.ResendDuplicatedMessage`.
4. Unlike a fixed `RetryInterval`, the delay follows the evidence: 30 seconds when `Demo.WMS` answers `503` with `Retry-After: 30`, 60 seconds or more for a `502`. A `Retry-After` sent by the target is also a minimum enforced by `Triage.Policy`, so the resend never comes earlier even if the model forgets to ask for a delay (seen once with DeepSeek, whose reason said "after 30s" while the call carried no delay).

In an early prototype the outage was simulated by pointing `Demo.ERP` to `localhost:1`. The agent called `get_component_settings`, compared `localhost:1` with the configured `HTTPPort`, and escalated: *"misconfigured endpoint rather than a transient outage"*. It was right, so the demo now uses a real `502` from a gateway.

`TriageProcess` is an ObjectScript `Ens.BusinessProcess` rather than BPL: it is generic infrastructure behind `Ens.Alert` that opens whatever message class failed, locks per error signature for coalescing and evaluates proposals with unit-tested rules. The operator still sees every step in the Visual Trace.

## Governance Rules

Why corrections are never automatic: an order with `ShipDate = "21/11/2026"` fails ISO-8601 validation. A model will rewrite it to `2026-11-21` with high confidence, because 21 cannot be a month. That is right only if the source system uses `DD/MM/YYYY`; if `21` was a typo for `10`, an automatic resend would put a valid-looking order with the wrong date into the ERP.

Three layers check every agent run:

1. **Tool authorization** (`Triage.Agent.ScopePolicy`, a `%AI.Policy.Authorization`): any call whose `incidentId` or `sessionId` differs from the current incident is denied, so a crafted payload cannot make the agent read or act on another session.
2. **Tool audit** (`Triage.Agent.AuditPolicy`, a `%AI.Policy.Audit`): every executed call is logged with arguments, a result preview and its duration in `Triage.Data.ToolCallLog`.
3. **Deterministic rules** (`Triage.Policy`) turn the proposal into one of three outcomes:
   - **ESCALATE**: unknown or empty action (default deny), `MaxAttempts` exceeded, or a patch that is invalid JSON, empty, names a property the message class does not have, touches `ProtectedFields`, or has a non-scalar value.
   - **APPROVAL**: confidence below `MinConfidence`, action not in `AutoActions`, or a patch that is not a `normalization` or touches a field outside `AutoFixFields`.
   - **EXECUTE**: everything else, such as `RETRY` above `MinConfidence` or a `normalization` limited to `AutoFixFields`.

An executed patch is applied to a clone of the failed message (`%ConstructClone()`), which is resent with `ResendDuplicatedMessage`; the original stays untouched in the Message Viewer. An operator who changes the patch before approving goes through the same checks, must write a note, and the incident keeps both the operator's values and the agent's proposal.

A resend only unblocks delivery: the source system still holds the same data. For recurring failures the agent adds an `upstreamRecommendation` (fix the source mapping or add a DTL conversion) and counts how often the same kind of failure was seen.

## Production Settings

All settings are on `Ens.Alert` (`Triage.Production.TriageProcess`), in the categories **Autonomy**, **Retry** and **Cost**.

| Setting | Demo value | Purpose |
|---|---|---|
| `AutoActions` | `RETRY,ESCALATE` | Actions that may run without approval. |
| `AutoFixFields` | `Currency,Warehouse` | Fields a `normalization` patch may change automatically. |
| `ProtectedFields` | `OrderId,CustomerId,Sku` | Fields no patch may change, even with approval. |
| `MinConfidence` | `0.7` | Lower confidence goes to approval. |
| `MaxAttempts` | `3` | Resends per root message before forcing escalation. |
| `MinRetryDelay` / `MaxRetryDelay` | `10` / `3600` | Limits for the retry delay, in seconds. |
| `RetryStagger` | `5` | Extra seconds per coalesced incident, so a recovering target is not flooded. |
| `CoalesceWindow` | `120` | Seconds in which the same error signature on the same component reuses an open decision with no LLM call. |
| `MaxAgentRunsPerMinute` | `10` | LLM budget for the production; alerts above it are escalated. |
| `AgentTimeout` | `180` | Seconds to wait for `Triage.AgentOperation` before escalating. |

## Agent Tools and Prompt Safety

`Triage.Agent.TriageAgent` has no tool that modifies or resends a message. Its tools (`Triage.Agent.Tools` plus two knowledge bases):

- `get_event_log(sessionId)`: the session's `Ens_Util.Log` entries.
- `get_component_settings(configName)`: the failing component's settings, with any setting named like `Key`, `Token`, `Password`, `Secret` or `Credentials` redacted.
- `get_attempt_history(incidentId)`: earlier failed attempts of the same root message (`RootHeaderId`).
- `get_similar_failures(configName, hours)`: the component's recent failures grouped by error pattern, to tell a one-off from a systemic problem.
- `lookup_error_code(code)`: exact IRIS error text (`$system.Status`) and the runbooks tagged with that code.
- `search_runbooks(query)`: vector search over the ten runbooks in `runbooks/`.
- `search_incidents(query)`: vector search over past incidents reviewed by a person.
- `submit_decision(...)`: the only way to answer (`action`, `reason`, `confidence`, `fixType`, `patch`, `retryAfterSeconds`, `upstreamRecommendation`).

Against prompt injection from payloads or error strings, `TriageAgent.Prompt()` escapes `<` and `>` and wraps external text in `<error_text>` and `<message_payload>` tags, telling the model to treat it as untrusted data.

## Knowledge and Operator Memory

1. **Exact codes** (`lookup_error_code`): small embeddings (FastEmbed `AllMiniLML6V2`, 384 dimensions) are unreliable for codes like `ERROR #6059` or `HTTP 422`, so they are looked up by SQL in the IRIS error dictionary and in the runbook tags.
2. **Runbooks** (`search_runbooks`): a `%AI.RAG.KnowledgeBase` with `%AI.RAG.Embedding.FastEmbed` and `%AI.RAG.VectorStore.IRIS`. `Triage.Knowledge.Base` splits the Markdown runbooks at their headings and indexes them during the Docker build, so the runtime needs no internet.
3. **Incident memory** (`search_incidents`): a second knowledge base with incidents approved, rejected or resolved by a person, with their note and any values they changed. Automatic decisions are never indexed, so the agent cannot reinforce its own mistakes. On **Run follow-up**, the agent finds the earlier incident and cites its number and ticket.

## How Replay Mode Stays Honest

When `LLM_API_KEY` is empty (or `LLM_PROVIDER=replay`), the dashboard shows a yellow banner, and every incident records `replay of <original model>` with the original run's date and tokens.

The production is not mocked: `TriageAgent.Replay()` builds a `%AI.ToolMgr` with the same tools, knowledge bases and policies, and runs the recorded tool calls against the live incident. Only the final reason text is the recorded one. A failure with no recording in `recordings/decisions.json` is escalated with *"Replay mode: no recorded decision for this failure"*.

## MCP Server

`Triage.MCP.Service` (`%AI.MCP.Service`) registers an MCP server at `/mcp/triage`, reached through the `iris-mcp-server` binary shipped with build 154 (`/usr/irissys/bin/iris-mcp-server`). It runs inside the container over `docker exec -i` (stdio), so no extra port or host dependency is needed.

Tools (`Triage.MCP.Tools`):

- `mcp_triage_get_triage_summary`: incidents by status, tokens and LLM runs saved.
- `mcp_triage_list_incidents(status, limit)`: incidents, for example `status="PENDING_APPROVAL"`.
- `mcp_triage_get_incident(incidentId)`: full detail, proposed patch and the tools the agent used.
- `mcp_triage_approve_incident(incidentId, note, patch)`: approves through `Triage.ReviewService`, as a step in the Visual Trace. The optional `patch`, such as `{"ShipDate":"2026-11-22"}`, replaces the agent's patch and passes the same rules.
- `mcp_triage_reject_incident(incidentId, note)`: nothing is executed and the incident stays with people.
- `mcp_triage_resolve_incident(incidentId, note)`: closes an escalated incident and adds the note to the incident memory.

`Triage.MCP.OperatorPolicy` (`%AI.Policy.Authorization`) refuses any write without a note; `Triage.MCP.AuditPolicy` logs every call, refused ones included.

Clients:

- **Claude Code:** `claude mcp add iris-triage -- docker exec -i iris-triage python3 /home/irisowner/dev/mcp/stdio_proxy.py` (in Git Bash, prefix `MSYS_NO_PATHCONV=1`).
- **Claude Desktop** (`claude_desktop_config.json`):
  ```json
  {
    "mcpServers": {
      "iris-triage": {
        "command": "docker",
        "args": ["exec", "-i", "iris-triage", "python3", "/home/irisowner/dev/mcp/stdio_proxy.py"]
      }
    }
  }
  ```
- **No client:** `python mcp/smoke_test.py` lists the six tools and prints the triage summary.

Why a proxy: current Claude Code versions first send a `server/discover` probe for a newer protocol. `iris-mcp-server` 2.0.0 rightly answers "Unsupported protocol version", but then stays in stateless mode: the `initialize` that follows succeeds while `tools/list` fails ("request _meta is missing…"). `mcp/stdio_proxy.py` answers the probe itself with the same error and passes everything else through. Clients that do not probe can run `/usr/irissys/bin/iris-mcp-server --config=/home/irisowner/dev/mcp/config.toml run` directly.

`mcp/config.toml` holds the container's demo credentials (`CSPSystem` for the gateway, `_SYSTEM` for IRIS); in a real deployment use `@{env:...}` or IRIS Wallet references.

## Dashboard

`web/index.html` is a static page with no dependencies, backed by `Triage.API.REST` (`/triage/api`). It signs in with IRIS credentials and records the user on every review; payloads and error texts are rendered as text nodes, never as HTML.

- Tiles: incidents, handled automatically, waiting, escalated, reviewed by people, LLM runs, LLM runs saved by coalescing, tokens, average decision time, and estimated cost when prices are set in `.env`.
- For each incident: the agent's reason, the upstream recommendation, the policy note, the patch as a before/after diff, the outcome of the resent message, every tool call with arguments, result and duration, and a link to the Visual Trace.
- **Approve**, **Reject** and **Mark as resolved** go through `Triage.ReviewService`, so each review is a step of the session. A proposed patch is editable: changed values turn the button into **Approve with my changes**.

## Measurements

On the ten demo failures with `deepseek/deepseek-v4.1-flash-1017` via OpenRouter:

| Metric | Value |
|---|---|
| Expected decisions | 10 / 10 in every run |
| Decision time, live | ~5–15 s per incident (average ~6–9 s) |
| Decision time, replay | ~30–400 ms, 0 tokens |
| Tool calls per decision | 3–10 |
| Tokens per decision | ~3,800–5,000 in, ~100–300 out (~1,700 in without the knowledge bases) |

A single agent with small read tools and deterministic rules after it was enough; splitting diagnosis and decision across `%AI.Agent.SubAgent`s or adding `%AI.Skills.Planning` would add LLM round trips, time and tokens under alert load.

With Gemini's free tier (20 requests a day per model) use **Quick demo**: a full demo needs 30–40 requests.

## Tests

`Triage.Test.PolicyTest` has 70 `%UnitTest` assertions: policy outcomes, patch validation, protected fields, retry delays and `Retry-After`, error signatures, secret redaction, session isolation, replay mode, operator patches and the MCP note requirement.

```bash
docker exec -it iris-triage iris session IRIS -U TRIAGE "##class(Triage.Setup).RunTests()"
```

The output ends with `All PASSED`.

## Plugging It Into Your Own Production

`TriageProcess` reads failed messages through class reflection (`%Dictionary.CompiledClass`) and `Ens.MessageHeader`, so it works with any message class:

1. Load `src/Triage` into your namespace (the `Demo` package is optional), index the runbooks with `do ##class(Triage.Knowledge.Base).LoadRunbooks("<path>/runbooks")`, and set the `LLM_*` variables for the IRIS process.
2. Add `Triage.Production.TriageProcess` named **`Ens.Alert`**, plus `Triage.Production.AgentOperation` (`Triage.AgentOperation`), `Triage.Production.EscalationOperation` (`Triage.EscalationOperation`), `Triage.Service.ReviewService` (`Triage.ReviewService`) and `Ens.Alarm`.
3. Set `AlertOnError = 1` on the operations to watch (and `AlertRetryGracePeriod` if they use `FailureTimeout`).
4. Choose `AutoFixFields` and `ProtectedFields` for your data.

## Reviews From the Terminal

From an IRIS terminal (`docker exec -it iris-triage iris session IRIS -U TRIAGE`):

```objectscript
// Approve (1) or reject (0) a PENDING_APPROVAL incident: Submit(incidentId, approved, operator, note, patch)
do ##class(Triage.Service.ReviewService).Submit(incidentId, 1, "_SYSTEM", "Customer uses DD/MM/YYYY")
// Approve with your own values instead of the agent's (FIX_AND_RESEND only; a note is required)
do ##class(Triage.Service.ReviewService).Submit(incidentId, 1, "_SYSTEM", "Customer confirmed the 22nd", "{""ShipDate"":""2026-11-22""}")

// Resolve an ESCALATED incident and add the note to the incident memory: Resolve(incidentId, note, operator)
do ##class(Triage.Service.ReviewService).Resolve(incidentId, "Renewed the API token of tenant C-0042", "_SYSTEM")

// Text report of all incidents
do ##class(Triage.Demo.Scenarios).Report()
```

The demos also run from the terminal: `do ##class(Triage.Demo.Scenarios).RunQuick()`, `.Run()` and `.RunFollowUp()`.

## Repository Layout

```text
src/Triage/            ObjectScript package loaded into namespace TRIAGE
  Agent/               TriageAgent (%AI.Agent), Tools (%AI.ToolSet), AuditPolicy, ScopePolicy
  Production/          Main (Production), TriageProcess (Ens.Alert), AgentOperation, EscalationOperation
  Policy.cls           Deterministic rules (EXECUTE / APPROVAL / ESCALATE)
  Data/                Incident, ToolCallLog, Recording (replay storage)
  Knowledge/           Base (%AI.RAG.KnowledgeBase setup and indexing), Runbook
  MCP/                 Service (%AI.MCP.Service), Tools, OperatorPolicy, AuditPolicy
  Service/             ReviewService (human reviews as steps of the production)
  API/REST.cls         REST API behind the dashboard (/triage/api)
  Demo/                InboundService, ERP and WMS operations, MockAPI, messages, Scenarios
  Test/PolicyTest.cls  %UnitTest suite (70 assertions)
  Setup.cls, Util.cls  Build-time setup, test runner, introspection helpers
runbooks/              Ten Markdown runbooks, indexed with FastEmbed at build time
recordings/            decisions.json, the recorded live runs used by replay mode
web/                   Dashboard served at /triage/index.html, with its favicon
assets/                Logo used by the README
mcp/                   config.toml for iris-mcp-server, stdio_proxy.py, smoke_test.py
Dockerfile             Image on top of the AI Hub build 154 image (IRIS_IMAGE)
docker-compose.yml     Container iris-triage, with the optional .env
merge.cpf, iris.script Build-time IRIS configuration and setup
.env.example           Template for provider, model, key and token prices
docs/                  This file and AIHUB-FEEDBACK.md
```
