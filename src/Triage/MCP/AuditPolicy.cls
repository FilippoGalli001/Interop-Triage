/// Persists every MCP tool call in Triage.Data.ToolCallLog, named "mcp:<tool>", under the incident it
/// concerns. Never write to the current device here: over MCP it is the JSON-RPC response.
Class Triage.MCP.AuditPolicy Extends %AI.Policy.Audit
{

Method %LogExecution(call As %DynamicObject, metadata As %DynamicObject, result As %DynamicObject, duration As %Integer, status As %Status) As %Status
{
    set args = ..Arguments(call)
    set log = ##class(Triage.Data.ToolCallLog).%New()
    set log.IncidentId = args.incidentId
    set log.ToolName = "mcp:" _ $zconvert(call.name, "L")
    set log.Arguments = args.%ToJSON()
    set log.Success = $$$ISOK(status)
    set log.DurationMs = duration
    if $$$ISOK(status) {
        set log.ResultPreview = $extract($select($isobject(result): result.%ToJSON(), 1: result), 1, 1000)
    } else {
        set log.Error = $system.Status.GetErrorText(status)
    }
    quit log.%Save()
}

/// The call's arguments as an object: over MCP they can arrive as a JSON string.
ClassMethod Arguments(call As %DynamicObject) As %DynamicObject
{
    set args = call.arguments
    quit:$isobject(args) args
    try {
        set args = ##class(%DynamicObject).%FromJSON(args)
    } catch {
        set args = {}
    }
    quit $select($isobject(args): args, 1: {})
}

/// Records a call that a policy denied, so refused attempts are visible too.
ClassMethod LogDenied(call As %DynamicObject, reason As %Status)
{
    set args = ..Arguments(call)
    set log = ##class(Triage.Data.ToolCallLog).%New()
    set log.IncidentId = args.incidentId
    set log.ToolName = "mcp:" _ $zconvert(call.name, "L")
    set log.Arguments = args.%ToJSON()
    set log.Success = 0
    set log.Error = "Denied: " _ $system.Status.GetErrorText(reason)
    do log.%Save()
}

}
