/// Runs the triage agent for one incident and returns its decision.
Class Triage.Production.AgentOperation Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnMessage(pRequest As Triage.Msg.TriageRequest, Output pResponse As Triage.Msg.TriageDecision) As %Status
{
    set sc = ##class(Triage.Agent.TriageAgent).Decide(pRequest.IncidentId)
    if $$$ISERR(sc) {
        // A rate limit of the LLM provider is transient: IRIS retries the run every RetryInterval
        // until FailureTimeout, like any other operation.
        set text = $system.Status.GetErrorText(sc)
        set ..Retry = (text [ "HTTP 429") || (text [ "Rate limit")
        if ..Retry {
            do ##class(Triage.Data.Incident).%OpenId(pRequest.IncidentId).ClearDecision()
        }
        quit sc
    }

    set incident = ##class(Triage.Data.Incident).%OpenId(pRequest.IncidentId)
    set pResponse = ##class(Triage.Msg.TriageDecision).%New()
    set pResponse.IncidentId = pRequest.IncidentId
    set pResponse.Action = incident.AgentAction
    set pResponse.Reason = incident.AgentReason
    set pResponse.Confidence = incident.AgentConfidence
    set pResponse.Patch = incident.AgentPatch
    $$$LOGINFO("Agent decision for incident " _ pRequest.IncidentId _ ": " _ incident.AgentAction _ " (" _ incident.AgentConfidence _ ", " _ incident.PromptTokens _ "+" _ incident.CompletionTokens _ " tokens)")
    quit $$$OK
}

}
