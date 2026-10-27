/// Actions taken through MCP must say why: approving, rejecting or resolving needs a note, which
/// becomes the reviewer's note on the incident and part of the agent's memory.
Class Triage.MCP.OperatorPolicy Extends %AI.Policy.Authorization
{

Parameter WRITETOOLS = "approve_incident,reject_incident,resolve_incident";

Method %CanExecute(toolref As %String, call As %DynamicObject, metadata As %DynamicObject) As %Status
{
    set name = $zconvert(call.name, "L")
    // Through MCP the tool name may carry the service prefix (mcp_triage_approve_incident).
    set writes = $listfromstring(..#WRITETOOLS)
    set write = 0
    for i=1:1:$listlength(writes) {
        set tool = $list(writes, i)
        set:$extract(name, *-$length(tool)+1, *)=tool write = 1
    }
    quit:'write $$$OK
    set note = ##class(Triage.MCP.AuditPolicy).Arguments(call).note
    if $zstrip(note, "<>W") = "" {
        set denied = $$$ERROR($$$GeneralError, "A note is required: say why, it is recorded with the review and kept in the agent's memory")
        do ##class(Triage.MCP.AuditPolicy).LogDenied(call, denied)
        quit denied
    }
    quit $$$OK
}

}
