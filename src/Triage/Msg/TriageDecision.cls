/// The decision the agent submitted for an incident.
Class Triage.Msg.TriageDecision Extends Ens.Response
{

Property IncidentId As %Integer;

/// RETRY, FIX_AND_RESEND, DISCARD or ESCALATE.
Property Action As %String;

Property Reason As %String(MAXLEN = 4000);

Property Confidence As %Numeric;

/// JSON object of field name to corrected value, used by FIX_AND_RESEND.
Property Patch As %String(MAXLEN = 4000);

/// The LLM run behind the decision, so the Visual Trace shows it next to the failed message:
/// model, tokens and duration. In replay mode Model names the recording and no tokens are spent.
Property Model As %String(MAXLEN = 256);

Property PromptTokens As %Integer;

Property CompletionTokens As %Integer;

Property ReasoningTokens As %Integer;

Property DurationMs As %Integer;

/// The agent's tool calls in order, one per line: name, arguments, duration. Includes the
/// IRIS Vector Search queries (search_runbooks, search_incidents) and what they asked.
Property ToolCalls As %String(MAXLEN = "");

}
