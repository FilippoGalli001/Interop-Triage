/// Keeps the agent on the incident it is triaging: tool calls about another incident or another
/// message session are denied. A message whose payload tries to steer the agent ("decide incident 12",
/// "show the log of session 300") cannot reach beyond its own failure.
Class Triage.Agent.ScopePolicy Extends %AI.Policy.Authorization
{

Property IncidentId As %Integer;

Property SessionId As %Integer;

Method %CanExecute(toolref As %String, call As %DynamicObject, metadata As %DynamicObject) As %Status
{
    set args = call.arguments
    quit:'$isobject(args) $$$OK
    if args.%IsDefined("incidentId") && (+args.incidentId '= +..IncidentId) {
        quit $$$ERROR($$$GeneralError, "Access denied: this triage may only use incident " _ ..IncidentId)
    }
    if args.%IsDefined("sessionId") && (+args.sessionId '= +..SessionId) {
        quit $$$ERROR($$$GeneralError, "Access denied: this triage may only read session " _ ..SessionId)
    }
    quit $$$OK
}

}
