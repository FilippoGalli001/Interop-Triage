/// Persists every tool call of the triage agent in Triage.Data.ToolCallLog.
Class Triage.Agent.AuditPolicy Extends %AI.Policy.Audit
{

Property IncidentId As %Integer;

Property CallCount As %Integer [ InitialExpression = 0 ];

Method %LogExecution(call As %DynamicObject, metadata As %DynamicObject, result As %DynamicObject, duration As %Integer, status As %Status) As %Status
{
    set ..CallCount = ..CallCount + 1
    set log = ##class(Triage.Data.ToolCallLog).%New()
    set log.IncidentId = ..IncidentId
    set log.ToolName = call.name
    set log.Arguments = $select($isobject(call.arguments): call.arguments.%ToJSON(), 1: call.arguments)
    set log.Success = $$$ISOK(status)
    set log.DurationMs = duration
    if $$$ISOK(status) {
        set log.ResultPreview = $extract($select($isobject(result): result.%ToJSON(), 1: result), 1, 1000)
    } else {
        set log.Error = $system.Status.GetErrorText(status)
    }
    quit log.%Save()
}

}
