/// Brings operator approvals and rejections into the production, so they appear in the Visual Trace.
Class Triage.Service.ReviewService Extends Ens.BusinessService
{

Property TargetConfigName As Ens.DataType.ConfigName [ InitialExpression = "Ens.Alert" ];

Parameter SETTINGS = "TargetConfigName:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId}";

Method OnProcessInput(pInput As Triage.Msg.ReviewRequest, Output pOutput As %RegisteredObject) As %Status
{
    quit ..SendRequestAsync(..TargetConfigName, pInput)
}

/// Approves or rejects an incident waiting for approval. Used by the dashboard, MCP and the terminal.
/// patch: for FIX_AND_RESEND, a JSON object that replaces the agent's patch, e.g. {"ShipDate":"2026-11-22"};
/// a changed patch needs a note, which the agent remembers for similar failures.
ClassMethod Submit(incidentId As %Integer, approved As %Boolean, operator As %String = {$username}, note As %String = "", patch As %String = "") As %Status
{
    set incident = ##class(Triage.Data.Incident).%OpenId(incidentId)
    quit:'$isobject(incident) $$$ERROR($$$GeneralError, "Unknown incident " _ incidentId)
    quit:incident.Status'="PENDING_APPROVAL" $$$ERROR($$$GeneralError, "Incident " _ incidentId _ " is " _ incident.Status _ ", not waiting for approval")
    set sc = ..CheckOperatorPatch(incident, approved, note, patch)
    quit:$$$ISERR(sc) sc

    set request = ##class(Triage.Msg.ReviewRequest).%New()
    set request.IncidentId = incidentId
    set request.Approved = approved
    set request.Operator = operator
    set request.Note = note
    set request.Patch = patch
    set sc = ##class(Ens.Director).CreateBusinessService("Triage.ReviewService", .service)
    quit:$$$ISERR(sc) sc
    quit service.ProcessInput(request)
}

/// Refuses an operator's patch at once, so the operator can correct it. The process checks it again
/// with all its rules before executing.
ClassMethod CheckOperatorPatch(incident As Triage.Data.Incident, approved As %Boolean, note As %String, patch As %String) As %Status
{
    quit:patch="" $$$OK
    quit:'approved $$$ERROR($$$GeneralError, "A patch can only be given when approving")
    quit:incident.AgentAction'="FIX_AND_RESEND" $$$ERROR($$$GeneralError, "The agent proposed " _ incident.AgentAction _ ", not FIX_AND_RESEND: there is no patch to change")
    quit:$zstrip(note, "<>W")="" $$$ERROR($$$GeneralError, "A note is required when you change the patch: say why, the agent remembers it")
    set config = {"protectedFields": (##class(Ens.Director).GetHostSettingValue("Ens.Alert", "ProtectedFields"))}
    set problem = ##class(Triage.Policy).CheckPatch(incident, config, , patch)
    quit:problem'="" $$$ERROR($$$GeneralError, problem)
    quit $$$OK
}

/// Closes an escalated incident with what the operator did. The note becomes part of the agent's memory.
ClassMethod Resolve(incidentId As %Integer, note As %String, operator As %String = {$username}) As %Status
{
    set incident = ##class(Triage.Data.Incident).%OpenId(incidentId)
    quit:'$isobject(incident) $$$ERROR($$$GeneralError, "Unknown incident " _ incidentId)
    quit:incident.Status'="ESCALATED" $$$ERROR($$$GeneralError, "Incident " _ incidentId _ " is " _ incident.Status _ ", not escalated")
    quit:note="" $$$ERROR($$$GeneralError, "A resolution note is required")
    set incident.Status = "RESOLVED"
    set incident.ReviewedBy = operator
    set incident.ReviewedAt = $zdatetime($horolog, 3)
    set incident.ReviewNote = note
    set sc = incident.%Save()
    quit:$$$ISERR(sc) sc
    quit ##class(Triage.Knowledge.Base).RememberIncident(incident)
}

}
