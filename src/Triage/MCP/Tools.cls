/// Tools offered to an operator's AI assistant over MCP (Claude Desktop, Claude Code...): the same
/// view and actions as the dashboard. Approvals go through the production like any other review.
/// DependsOn: the ToolSet generator needs the policy classes of the XData compiled first.
Class Triage.MCP.Tools Extends %AI.ToolSet [ DependsOn = (Triage.MCP.OperatorPolicy, Triage.MCP.AuditPolicy) ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="TriageOperator">
  <Description>Interoperability failure triage: incidents, agent decisions and operator reviews</Description>
  <Policies>
    <Authorization Class="Triage.MCP.OperatorPolicy" />
    <Audit Class="Triage.MCP.AuditPolicy" />
  </Policies>
  <Tool Name="get_triage_summary" Method="GetSummary"/>
  <Tool Name="list_incidents" Method="ListIncidents"/>
  <Tool Name="get_incident" Method="GetIncident"/>
  <Tool Name="approve_incident" Method="ApproveIncident"/>
  <Tool Name="reject_incident" Method="RejectIncident"/>
  <Tool Name="resolve_incident" Method="ResolveIncident"/>
</ToolSet>
}

/// Returns the triage numbers as JSON: incidents, how many were handled automatically, how many
/// wait for approval or are escalated, agent runs, LLM runs saved, tokens, live or replay mode.
ClassMethod GetSummary() As %String
{
    quit ##class(Triage.API.REST).StatsJSON().%ToJSON()
}

/// Lists recent incidents, newest first, as JSON. status filters them, for example
/// PENDING_APPROVAL (waiting for an operator), ESCALATED (open for a person), RESENT, DISCARDED;
/// empty for all. Each item has the message, the error, the agent's proposal and the status.
ClassMethod ListIncidents(status As %String = "", limit As %Integer = 20) As %String
{
    set rows = []
    set sql = "SELECT TOP ? %ID FROM Triage_Data.Incident" _ $select(status '= "": " WHERE Status = ?", 1: "") _ " ORDER BY %ID DESC"
    set rs = $select(status '= "": ##class(%SQL.Statement).%ExecDirect(, sql, +limit, $zconvert(status, "U")), 1: ##class(%SQL.Statement).%ExecDirect(, sql, +limit))
    while rs.%Next() {
        set incident = ##class(Triage.Data.Incident).%OpenId(rs.ID)
        do rows.%Push({
            "id": (+rs.ID), "time": (incident.CreatedAt), "component": (incident.SourceConfigName),
            "message": (incident.MessageBody), "error": ($extract(incident.AlertText, 1, 300)),
            "agentProposal": (incident.AgentAction), "patch": (incident.AgentPatch), "confidence": (incident.AgentConfidence),
            "status": (incident.Status), "executed": (incident.FinalAction), "resendOutcome": (incident.ResendOutcome())
        })
    }
    quit rows.%ToJSON()
}

/// Returns one incident in full as JSON: error, message and proposed patch, the agent's reasoning
/// and upstream advice, what the rules did, the operator review, and the tools the agent used.
ClassMethod GetIncident(incidentId As %Integer) As %String
{
    set incident = ##class(Triage.Data.Incident).%OpenId(incidentId)
    quit:'$isobject(incident) {"error": ("unknown incident " _ incidentId)}.%ToJSON()
    set json = ##class(Triage.API.REST).ToJSON(incident)
    set tools = []
    set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ToolName FROM Triage_Data.ToolCallLog WHERE IncidentId = ? AND ToolName NOT LIKE 'mcp:%' ORDER BY %ID", incidentId)
    while rs.%Next() {
        do tools.%Push($zconvert(rs.ToolName, "L"))
    }
    set json.agentToolCalls = tools
    quit json.%ToJSON()
}

/// Approves the agent's proposal for an incident waiting for approval (status PENDING_APPROVAL):
/// the production then executes it (resend, patched resend or discard). note: why you approve,
/// kept in the agent's memory for similar failures. Required. patch: optional, only for
/// FIX_AND_RESEND, a JSON object with the field values to apply instead of the agent's patch,
/// e.g. {"ShipDate":"2026-11-22"}; the same rules check it (protected and unknown fields are refused).
ClassMethod ApproveIncident(incidentId As %Integer, note As %String, patch As %String = "") As %String
{
    quit ..Answer(##class(Triage.Service.ReviewService).Submit(incidentId, 1, ..Operator(), note, patch), "Approved incident " _ incidentId _ $select(patch'="": " with your patch", 1: "") _ ": the production executes the decision now.")
}

/// Rejects the agent's proposal for an incident waiting for approval: nothing is executed and the
/// incident stays with the people. note: why, kept in the agent's memory. Required.
ClassMethod RejectIncident(incidentId As %Integer, note As %String) As %String
{
    quit ..Answer(##class(Triage.Service.ReviewService).Submit(incidentId, 0, ..Operator(), note), "Rejected the proposal for incident " _ incidentId _ ".")
}

/// Closes an escalated incident (status ESCALATED) once a person fixed the cause. note: what was
/// done; it becomes part of the agent's memory for similar failures. Required.
ClassMethod ResolveIncident(incidentId As %Integer, note As %String) As %String
{
    quit ..Answer(##class(Triage.Service.ReviewService).Resolve(incidentId, note, ..Operator()), "Resolved incident " _ incidentId _ ".")
}

/// The reviewer recorded for actions taken through MCP.
ClassMethod Operator() As %String
{
    quit $username _ " via MCP"
}

ClassMethod Answer(sc As %Status, done As %String) As %String
{
    quit $select($$$ISOK(sc): done, 1: "Not done: " _ $system.Status.GetErrorText(sc))
}

}
