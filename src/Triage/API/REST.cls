/// JSON API of the triage dashboard, at /triage/api. Password authentication: the IRIS user who
/// approves or resolves an incident is recorded as the operator. The page itself is web/index.html,
/// served as a static file at /triage/.
Class Triage.API.REST Extends %CSP.REST
{

Parameter CONTENTTYPE = "application/json";

Parameter CHARSET = "utf-8";

Parameter UseSession = 0;

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
  <Route Url="/stats" Method="GET" Call="Stats"/>
  <Route Url="/incidents" Method="GET" Call="Incidents"/>
  <Route Url="/incidents/:id" Method="GET" Call="Incident"/>
  <Route Url="/incidents/:id/approve" Method="POST" Call="Approve"/>
  <Route Url="/incidents/:id/reject" Method="POST" Call="Reject"/>
  <Route Url="/incidents/:id/resolve" Method="POST" Call="Resolve"/>
  <Route Url="/demo/:act" Method="POST" Call="Demo"/>
</Routes>
}

/// Fields of an incident returned by the API.
Parameter FIELDS = "ReplayOf,CreatedAt,SourceConfigName,SessionId,AttemptNumber,AlertText,MessageClass,MessageBody,AgentAction,AgentConfidence,AgentFixType,AgentPatch,AgentRetryAfter,RetryDelay,AgentReason,UpstreamRecommendation,LeaderIncidentId,FinalAction,GuardrailNote,Status,ResendHeaderId,ReviewedBy,ReviewedAt,ReviewNote,OperatorPatch,Model,PromptTokens,CompletionTokens,ReasoningTokens,ToolCalls,AgentDurationMs,AgentError";

ClassMethod Stats() As %Status
{
    write ..StatsJSON().%ToJSON()
    quit $$$OK
}

/// The dashboard numbers, also used by the MCP tools.
ClassMethod StatsJSON() As %DynamicObject
{
    set rs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT COUNT(*) AS Total, SUM(CASE WHEN Model IS NOT NULL THEN 1 ELSE 0 END) AS AgentRuns, " _
        "SUM(CASE WHEN LeaderIncidentId IS NOT NULL THEN 1 ELSE 0 END) AS Reused, " _
        "SUM(CASE WHEN ReviewedBy IS NULL AND Status IN ('RESENT','DISCARDED','SCHEDULED_RETRY') THEN 1 ELSE 0 END) AS Automatic, " _
        "SUM(CASE WHEN Status = 'PENDING_APPROVAL' THEN 1 ELSE 0 END) AS Pending, " _
        "SUM(CASE WHEN Status = 'ESCALATED' THEN 1 ELSE 0 END) AS Escalated, " _
        "SUM(CASE WHEN ReviewedBy IS NOT NULL THEN 1 ELSE 0 END) AS Reviewed, " _
        "SUM(PromptTokens) AS PromptTokens, SUM(CompletionTokens) AS CompletionTokens, AVG(AgentDurationMs) AS AvgMs " _
        "FROM Triage_Data.Incident")
    do rs.%Next()
    set stats = {
        "incidents": (+rs.Total), "agentRuns": (+rs.AgentRuns), "reusedDecisions": (+rs.Reused),
        "automatic": (+rs.Automatic), "pending": (+rs.Pending), "escalated": (+rs.Escalated), "reviewed": (+rs.Reviewed),
        "promptTokens": (+rs.PromptTokens), "completionTokens": (+rs.CompletionTokens), "avgDecisionMs": (rs.AvgMs \ 1),
        "provider": (##class(Triage.Util).Env("LLM_PROVIDER")), "model": (##class(Triage.Util).Env("LLM_MODEL")),
        "mode": ($select(##class(Triage.Agent.TriageAgent).ReplayMode(): "replay", 1: "live"))
    }
    set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N, MAX(%EXACT(Model)) AS Model FROM Triage_Data.Recording")
    do rs.%Next()
    set stats.recordings = +rs.N, stats.recordedModel = rs.Model
    // Optional prices (per million tokens) give a cost estimate.
    set priceIn = ##class(Triage.Util).Env("LLM_PRICE_INPUT_PER_MTOK"), priceOut = ##class(Triage.Util).Env("LLM_PRICE_OUTPUT_PER_MTOK")
    if (priceIn '= "") || (priceOut '= "") {
        set stats.estimatedCost = $fnumber((stats.promptTokens * priceIn + (stats.completionTokens * priceOut)) / 1000000, "", 4)
    }
    quit stats
}

ClassMethod Incidents() As %Status
{
    set rows = []
    set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 200 %ID FROM Triage_Data.Incident ORDER BY %ID DESC")
    while rs.%Next() {
        do rows.%Push(..ToJSON(##class(Triage.Data.Incident).%OpenId(rs.ID)))
    }
    write rows.%ToJSON()
    quit $$$OK
}

ClassMethod Incident(id As %Integer) As %Status
{
    set incident = ##class(Triage.Data.Incident).%OpenId(id)
    quit:'$isobject(incident) ..NotFound(id)
    set json = ..ToJSON(incident)
    set calls = []
    set rs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT Timestamp, ToolName, Arguments, Success, DurationMs, ResultPreview, Error FROM Triage_Data.ToolCallLog WHERE IncidentId = ? ORDER BY %ID", id)
    while rs.%Next() {
        do calls.%Push({"time": (rs.Timestamp), "tool": ($zconvert(rs.ToolName, "L")), "arguments": (rs.Arguments), "success": (+rs.Success), "ms": (+rs.DurationMs), "result": (rs.ResultPreview), "error": (rs.Error)})
    }
    set json.toolCalls = calls
    set recording = ##class(Triage.Data.Recording).%OpenId(incident.ReplayOf)
    if $isobject(recording) {
        set json.replay = {"model": (recording.Model), "provider": (recording.Provider), "recordedAt": (recording.RecordedAt), "promptTokens": (recording.PromptTokens), "completionTokens": (recording.CompletionTokens)}
    }
    write json.%ToJSON()
    quit $$$OK
}

ClassMethod Approve(id As %Integer) As %Status
{
    quit ..Answer(##class(Triage.Service.ReviewService).Submit(id, 1, $username, ..BodyNote(), ..BodyPatch()))
}

ClassMethod Reject(id As %Integer) As %Status
{
    quit ..Answer(##class(Triage.Service.ReviewService).Submit(id, 0, $username, ..BodyNote()))
}

ClassMethod Resolve(id As %Integer) As %Status
{
    quit ..Answer(##class(Triage.Service.ReviewService).Resolve(id, ..BodyNote(), $username))
}

/// Starts the demo in the background: "run" resets and sends all scenarios, "followup" sends the second act.
ClassMethod Demo(act As %String) As %Status
{
    if act = "run" {
        job ##class(Triage.Demo.Scenarios).Run()
    } elseif act = "quick" {
        job ##class(Triage.Demo.Scenarios).RunQuick()
    } elseif act = "followup" {
        job ##class(Triage.Demo.Scenarios).RunFollowUp()
    } else {
        quit ..NotFound(act)
    }
    write {"started": (act)}.%ToJSON()
    quit $$$OK
}

ClassMethod ToJSON(incident As Triage.Data.Incident) As %DynamicObject
{
    set json = {"id": (+incident.%Id())}
    set fields = $listfromstring(..#FIELDS)
    for i=1:1:$listlength(fields) {
        set name = $list(fields, i)
        do json.%Set($zconvert($extract(name), "L") _ $extract(name, 2, *), $property(incident, name))
    }
    set json.resendOutcome = incident.ResendOutcome()
    quit json
}

ClassMethod BodyNote() As %String
{
    set note = ""
    try {
        set note = ##class(%DynamicObject).%FromJSON(%request.Content).note
    } catch {
    }
    quit note
}

/// The patch an operator wrote instead of the agent's, as a JSON string ("" when none).
ClassMethod BodyPatch() As %String
{
    set patch = ""
    try {
        set patch = ##class(%DynamicObject).%FromJSON(%request.Content).patch
        set:$isobject(patch) patch = patch.%ToJSON()
    } catch {
    }
    quit patch
}

/// Writes {"ok":1} or the error with status 400.
ClassMethod Answer(sc As %Status) As %Status
{
    if $$$ISERR(sc) {
        set %response.Status = ..#HTTP400BADREQUEST
        write {"error": ($system.Status.GetErrorText(sc))}.%ToJSON()
    } else {
        write {"ok": 1}.%ToJSON()
    }
    quit $$$OK
}

ClassMethod NotFound(what As %String) As %Status
{
    set %response.Status = ..#HTTP404NOTFOUND
    write {"error": ("not found: " _ what)}.%ToJSON()
    quit $$$OK
}

}
