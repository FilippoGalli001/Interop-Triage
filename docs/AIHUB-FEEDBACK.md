# Feedback on AI Hub EAP (Build 154)

Every item was observed while building this project on `2026.3.0AI.154.0`.

## What Worked Well

- **Declarative agents.** `PROVIDERCONFIG` with `@{env:LLM_PROVIDER}` and `@{env:LLM_API_KEY}` switches between OpenRouter (DeepSeek) and Gemini by editing `.env`, with no code change.
- **Tools from method signatures.** A `%AI.ToolSet` turns ObjectScript class methods into tools; the same mechanism behind `%AI.MCP.Service` became an MCP server for operators with a web application and a TOML file.
- **Policies on the toolset.** `%AI.Policy.Authorization` gave per-incident scoping (`Triage.Agent.ScopePolicy`) and `%AI.Policy.Audit` a complete tool-call trail, without touching the prompt or the agent loop.
- **Loop protection.** When a model kept repeating an identical tool call, the loop stopped on its own (`<%AICore>LoopDetected`) instead of spending tokens, and the production escalated the incident. `submit_decision` now accepts a missing `fixType` as `correction` instead of rejecting it.
- **RAG with no external service.** `%AI.RAG.KnowledgeBase` with FastEmbed and the IRIS vector store indexed the runbooks in minutes, and the search tools can be called through `%AI.ToolMgr` without an LLM, which made them easy to test.

## What Broke or Needed a Workaround

| Observation | Workaround |
|---|---|
| No documented structured-output option on `%AI.Agent`. | The agent can only answer through the `submit_decision` tool, whose arguments `Triage.Policy` validates. |
| `KnowledgeBase.AddDocument` does not split long texts. | Runbooks are split at their `## ` headings before indexing (`Triage.Knowledge.Base.Sections`). |
| FastEmbed downloads its model from Hugging Face on first use (about 10 s, needs network). | Runbooks are indexed during `docker build`, so the image holds the model and the runtime needs no internet. |
| A `%LogExecution` override in a `%AI.Policy.Audit` subclass must be declared `As %Status`, which was not obvious. | Declared explicitly in both audit policies. |
| `LoadDir` compiles a toolset whose XData `<Policies>` names policy classes before those classes, which fails in `%GetAuditPolicy` during the build. | `DependsOn` on the toolset class (`Triage.MCP.Tools`). |
| Over MCP, `call.arguments` arrives as a JSON string in the audit policy but as an object in the authorization policy. | Arguments are normalized in `Triage.MCP.AuditPolicy.Arguments`. |
| Calls denied by an authorization policy never reach the audit policy, so refusals leave no trace. | The authorization policy logs its own denials (`Triage.MCP.AuditPolicy.LogDenied`). |
| Tool names can arrive uppercased in `call.name` (`GET_EVENT_LOG`), depending on the provider. | Tool names are compared in lower case. |
| `response.Usage` differs between providers: Gemini reports reasoning tokens only inside `total_tokens`, and after a tool loop the counts look cumulative. | Usage is read defensively; reasoning tokens are total − prompt − completion when the provider omits them. |
| A model can return a tool call as plain text: DeepSeek through OpenRouter once wrote `submit_decision` in its own markup (`<｜DSML｜invoke name="submit_decision">…`), so `Chat` returned text and no tool ran. | When no decision was recorded, `Triage.Agent.TriageAgent.Decide` reminds the model once in the same session; otherwise the incident is escalated. |
| `iris-mcp-server` 2.0.0 is in `/usr/irissys/bin` but not on the `PATH`. | The MCP configuration uses the full path. |
| After rejecting a `server/discover` probe (sent first by current Claude Code versions, protocol `2026-07-28`), `iris-mcp-server` 2.0.0 stays in stateless mode: the following `initialize` succeeds but `tools/list` fails with "request _meta is missing or has malformed required fields", so Claude Code connects with no tools. Reproduced with a raw JSON-RPC sequence (probe, `initialize`, `tools/list`); reported as [ai-hub-eap#39](https://github.com/intersystems-community/ai-hub-eap/issues/39). | `mcp/stdio_proxy.py` answers the probe itself and passes everything else through; verified with Claude Code 2.1.311. |
| Some documentation pages describe a later build than the contest image. | Every `%AI.*` class and signature used here was checked against the build 154 image itself. |

## What We Would Like to See

- A structured-output option on `%AI.Agent` (a JSON schema for the final answer), so a decision tool is not the only way to get typed results.
- A `Usage` object with the same keys across providers, including reasoning tokens.
- An audit hook for calls denied by an authorization policy.
- A ready-made business operation that runs a `%AI.Agent` inside a production with timeout and retry settings; `Triage.Production.AgentOperation` is our version of it.
- A way to ship the FastEmbed model with the kit for air-gapped installations.

## IRIS Agentic Dev

[IRIS Agentic Dev](https://github.com/intersystems-community/iris-agentic-dev) (v1.6.1) was used in the second half of the project: compiling a local file with one command and structured errors, running code, and reading production status, the Event Log and queues as JSON. One problem: `iris_test` returned `NO_TESTS_FOUND` for test classes that were already compiled, because it looks for files under `^UnitTestRoot`; tests were run with `iris_execute` and `do ##class(Triage.Setup).RunTests()` instead.
