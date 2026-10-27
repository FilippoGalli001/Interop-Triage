/// One failed message reported by an alert, with the agent's decision and what was done.
Class Triage.Data.Incident Extends %Persistent
{

Property CreatedAt As %TimeStamp [ InitialExpression = {$zdatetime($horolog, 3)} ];

/// Component that raised the alert.
Property SourceConfigName As %String(MAXLEN = 256);

Property SessionId As %Integer;

Property AlertText As %String(MAXLEN = "");

/// Header of the request that failed.
Property FailedHeaderId As %Integer;

/// Header of the first message in the resend chain, shared by all its attempts.
Property RootHeaderId As %Integer;

/// 1 for the original message, 2 for its first resend, and so on.
Property AttemptNumber As %Integer [ InitialExpression = 1 ];

Property MessageClass As %String(MAXLEN = 256);

Property MessageBodyId As %String;

/// Body of the failed message as JSON, as shown to the agent.
Property MessageBody As %String(MAXLEN = "");

/// Decision submitted by the agent.
Property AgentAction As %String;

Property AgentReason As %String(MAXLEN = "");

Property AgentConfidence As %Numeric;

Property AgentPatch As %String(MAXLEN = "");

/// For RETRY: seconds the agent asked to wait before resending (0 = at once).
Property AgentRetryAfter As %Integer;

/// Seconds actually waited before the resend, after limits and staggering.
Property RetryDelay As %Integer;

/// For FIX_AND_RESEND: "normalization" (same value, canonical form) or "correction" (different value).
Property AgentFixType As %String;

/// Agent's advice for removing the cause upstream (mapping, DTL, settings), if any.
Property UpstreamRecommendation As %String(MAXLEN = "");

/// Failing component plus the error text without ids and numbers: equal for alerts of one cause.
Property ErrorSignature As %String(MAXLEN = 1000);

/// Incident whose decision this one reused instead of calling the agent (alert storm).
Property LeaderIncidentId As %Integer;

/// Action actually executed after the guardrails.
Property FinalAction As %String;

/// Why the guardrails changed the agent's action, if they did.
Property GuardrailNote As %String(MAXLEN = "");

/// NEW, ANALYZING, DECIDED, PENDING_APPROVAL, SCHEDULED_RETRY, RESENT, DISCARDED, ESCALATED, REJECTED or RESOLVED.
Property Status As %String [ InitialExpression = "NEW" ];

Property ReviewedBy As %String(MAXLEN = 128);

Property ReviewedAt As %TimeStamp;

Property ReviewNote As %String(MAXLEN = "");

/// The patch the operator applied instead of the agent's, when they changed it before approving.
Property OperatorPatch As %String(MAXLEN = "");

Property ResendHeaderId As %Integer;

Property Model As %String(MAXLEN = 256);

/// Recording whose calls were replayed, in replay mode (no LLM was called).
Property ReplayOf As %Integer;

Property PromptTokens As %Integer;

Property CompletionTokens As %Integer;

Property ReasoningTokens As %Integer;

Property ToolCalls As %Integer;

Property AgentDurationMs As %Integer;

Property AgentError As %String(MAXLEN = "");

Index RootIdx On RootHeaderId;

Index SignatureIdx On ErrorSignature;

/// Replaces quoted values with '?' and numbers with N, keeping error codes (#6059).
ClassMethod Signature(source As %String, text As %String) As %String
{
    set text = ##class(%Regex.Matcher).%New("'[^']*'", text).ReplaceAll("'?'")
    set text = ##class(%Regex.Matcher).%New("(?<![#\w])-?\d+([.:/-]\d+)*", text).ReplaceAll("N")
    quit $extract(source _ "|" _ text, 1, 1000)
}

/// Forgets a partial agent run, so that it can start again from scratch.
Method ClearDecision() As %Status
{
    for prop = "AgentAction", "AgentReason", "AgentConfidence", "AgentPatch", "AgentFixType", "AgentRetryAfter", "UpstreamRecommendation", "AgentError" {
        set $property($this, prop) = ""
    }
    set ..Status = "ANALYZING"
    quit ..%Save()
}

/// What happened to the resent message: SUCCEEDED, FAILED_AGAIN, PENDING, or "" when nothing was resent.
/// Read from the message header, so automatic outcomes stay visible without entering the agent's memory.
Method ResendOutcome() As %String
{
    quit:..ResendHeaderId="" ""
    set header = ##class(Ens.MessageHeader).%OpenId(..ResendHeaderId)
    quit:'$isobject(header) ""
    set status = header.StatusLogicalToDisplay(header.Status)
    quit $case(status, "Completed": "SUCCEEDED", "Error": "FAILED_AGAIN", "Aborted": "FAILED_AGAIN", "Discarded": "FAILED_AGAIN", : "PENDING")
}

/// Creates and saves an incident from an alert raised by a failing component.
ClassMethod CreateFromAlert(alert As Ens.AlertRequest, Output incident As Triage.Data.Incident) As %Status
{
    set incident = ..%New()
    set incident.SourceConfigName = alert.SourceConfigName
    set incident.SessionId = alert.SessionId
    set incident.AlertText = alert.AlertText
    set incident.ErrorSignature = ..Signature(alert.SourceConfigName, alert.AlertText)

    // The failed message is the last request this component received in the session.
    set headerId = ""
    &sql(SELECT TOP 1 %ID INTO :headerId FROM Ens.MessageHeader
         WHERE SessionId = :alert.SessionId AND TargetConfigName = :alert.SourceConfigName
           AND Type = 1
         ORDER BY %ID DESC)
    if SQLCODE = 0 {
        set header = ##class(Ens.MessageHeader).%OpenId(headerId)
        set incident.FailedHeaderId = headerId
        set incident.MessageClass = header.MessageBodyClassName
        set incident.MessageBodyId = header.MessageBodyId
        set incident.RootHeaderId = $get(^Triage.Resend(headerId), headerId)
        set body = $classmethod(header.MessageBodyClassName, "%OpenId", header.MessageBodyId)
        set incident.MessageBody = ##class(Triage.Util).ToJSON(body).%ToJSON()

        set previous = 0
        &sql(SELECT COUNT(*) INTO :previous FROM Triage_Data.Incident
             WHERE RootHeaderId = :incident.RootHeaderId)
        set incident.AttemptNumber = previous + 1
    }
    quit incident.%Save()
}

}
