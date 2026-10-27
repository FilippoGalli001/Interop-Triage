/// Tools the triage agent uses to inspect a failure and to submit its decision.
Class Triage.Agent.Tools Extends %AI.ToolSet
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="TriageTools">
  <Tool Name="get_event_log" Method="GetEventLog"/>
  <Tool Name="get_component_settings" Method="GetComponentSettings"/>
  <Tool Name="get_attempt_history" Method="GetAttemptHistory"/>
  <Tool Name="get_similar_failures" Method="GetSimilarFailures"/>
  <Tool Name="lookup_error_code" Method="LookupErrorCode"/>
  <Tool Name="submit_decision" Method="SubmitDecision"/>
</ToolSet>
}

/// Settings whose name contains one of these words are never shown to the model.
Parameter SECRETWORDS = "password,secret,token,key,credential";

/// Returns the Interoperability Event Log entries (errors, warnings, info) of a message session,
/// newest first, as a JSON array. Use it to see what happened around the failure.
ClassMethod GetEventLog(sessionId As %Integer) As %String
{
    set rows = []
    set rs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT TOP 20 TimeLogged, %EXTERNAL(Type) AS Type, ConfigName, Text FROM Ens_Util.Log WHERE SessionId = ? ORDER BY %ID DESC",
        sessionId)
    while rs.%Next() {
        do rows.%Push({"time": (rs.TimeLogged), "type": (rs.Type), "component": (rs.ConfigName), "text": (rs.Text)})
    }
    quit rows.%ToJSON()
}

/// Returns the class and the configured settings (for example RetryInterval, FailureTimeout,
/// AlertRetryGracePeriod, ReplyCodeActions, target URLs) of a production component, as JSON.
/// Settings not listed keep their defaults. Secret values are redacted.
ClassMethod GetComponentSettings(configName As %String) As %String
{
    set sc = ##class(Ens.Director).GetProductionStatus(.productionName, .state)
    set production = ##class(Ens.Config.Production).%OpenId(productionName)
    quit:'$isobject(production) {"error": "no production is running"}.%ToJSON()

    for i=1:1:production.Items.Count() {
        set item = production.Items.GetAt(i)
        continue:item.Name'=configName
        set settings = {}
        for j=1:1:item.Settings.Count() {
            set setting = item.Settings.GetAt(j)
            do settings.%Set(setting.Name, $select(..IsSecret(setting.Name): "***REDACTED***", 1: setting.Value))
        }
        quit
    }
    quit:'$data(settings) {"error": ("unknown component " _ configName)}.%ToJSON()
    quit {"name": (item.Name), "class": (item.ClassName), "enabled": (item.Enabled), "poolSize": (item.PoolSize), "settings": (settings)}.%ToJSON()
}

/// Returns the earlier incidents of the same original message (previous failed attempts and
/// what was decided for them), oldest first, as a JSON array. Empty when this is the first failure.
ClassMethod GetAttemptHistory(incidentId As %Integer) As %String
{
    set rows = []
    set incident = ##class(Triage.Data.Incident).%OpenId(incidentId)
    quit:'$isobject(incident) rows.%ToJSON()
    set rs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT %ID, CreatedAt, AttemptNumber, AlertText, FinalAction, AgentReason FROM Triage_Data.Incident WHERE RootHeaderId = ? AND %ID < ? ORDER BY %ID",
        incident.RootHeaderId, incidentId)
    while rs.%Next() {
        set outcome = ##class(Triage.Data.Incident).%OpenId(rs.ID).ResendOutcome()
        do rows.%Push({"incident": (rs.ID), "time": (rs.CreatedAt), "attempt": (rs.AttemptNumber), "error": (rs.AlertText), "action": (rs.FinalAction), "reason": (rs.AgentReason), "resendOutcome": (outcome)})
    }
    quit rows.%ToJSON()
}

/// Counts the recent failures of the same production component, grouped by error pattern
/// (ids and numbers removed), with the decisions taken, as JSON. Use it to tell a one-off
/// problem from a recurring one whose cause should be fixed upstream.
ClassMethod GetSimilarFailures(configName As %String, hours As %Integer = 24) As %String
{
    set since = $system.SQL.Functions.DATEADD("hh", -hours, $zdatetime($horolog, 3))
    set rows = []
    set rs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT ErrorSignature, COUNT(*) AS Failures, LIST(DISTINCT FinalAction) AS Actions, MAX(CreatedAt) AS Last FROM Triage_Data.Incident WHERE SourceConfigName = ? AND CreatedAt >= ? GROUP BY ErrorSignature ORDER BY Failures DESC",
        configName, since)
    while rs.%Next() {
        do rows.%Push({"errorPattern": ($piece(rs.ErrorSignature, "|", 2, *)), "failures": (rs.Failures), "actions": (rs.Actions), "last": (rs.Last)})
    }
    quit {"component": (configName), "hours": (hours), "patterns": (rows)}.%ToJSON()
}

/// Looks up an error code exactly: an IRIS error number (6059 or #6059), a named Interoperability
/// error (<Ens>ErrFailureTimeout) or an HTTP status ("HTTP 401"). Returns the official IRIS message
/// text for IRIS codes, and the full text of the runbooks that cover the code, as JSON.
ClassMethod LookupErrorCode(code As %String) As %String
{
    set code = $zstrip(code, "<>W")
    set result = {"code": (code)}
    if $zconvert(code, "U")?1"HTTP".1" "3N {
        set key = "HTTP " _ $extract(code, *-2, *)
    } elseif code [ "<Ens>" {
        set key = code
    } else {
        set number = $zstrip(code, "*E", "", "0123456789")
        quit:number="" {"code": (code), "error": "not an IRIS error number, named error or HTTP status"}.%ToJSON()
        set key = "#" _ number
        set result.officialText = $system.Status.GetErrorText($system.Status.Error(+number))
    }
    set result.key = key
    set runbooks = []
    set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Triage_Knowledge.Runbook ORDER BY Name")
    while rs.%Next() {
        set runbook = ##class(Triage.Knowledge.Runbook).%OpenId(rs.ID)
        do:runbook.Covers(key) runbooks.%Push({"runbook": (runbook.Name), "title": (runbook.Title), "text": (runbook.Body)})
    }
    set result.runbooks = runbooks
    quit result.%ToJSON()
}

/// Records your final decision for the incident. Call it exactly once, as your last step.
/// action: RETRY (transient problem, resend unchanged), FIX_AND_RESEND (the data is wrong and the
/// correct value is certain; put the corrected fields in patch), DISCARD (the message must not be
/// processed, for example an exact duplicate), ESCALATE (a human must act).
/// reason: short explanation for the operator, citing the evidence.
/// confidence: from 0 to 1.
/// patch: object of field name to corrected value for FIX_AND_RESEND, otherwise {}.
/// fixType: for FIX_AND_RESEND, "normalization" when the value stays the same and only its form
/// changes (for example a currency name to its ISO code), "correction" when the value changes.
/// Anything else, or nothing, is recorded as "correction".
/// upstreamRecommendation: optional advice to remove the cause upstream (source mapping, DTL,
/// component settings such as ReplyCodeActions), when the problem is recurring or systemic.
/// retryAfterSeconds: for RETRY, how long to wait before the resend so the target can recover;
/// 0 resends at once. Never earlier than a Retry-After the target sent.
ClassMethod SubmitDecision(incidentId As %Integer, action As %String, reason As %String, confidence As %Float, patch As %DynamicObject, fixType As %String = "", upstreamRecommendation As %String = "", retryAfterSeconds As %Integer = "") As %String
{
    set action = $zconvert(action, "U")
    quit:'##class(Triage.Policy).InList(##class(Triage.Policy).#ACTIONS, action) "Rejected: action must be one of " _ ##class(Triage.Policy).#ACTIONS
    quit:(confidence < 0)||(confidence > 1) "Rejected: confidence must be between 0 and 1"
    // A missing or unknown fixType becomes "correction", which is never automatic. Rejecting it made
    // a model resend the same call until AI Hub stopped the loop.
    set fixType = $zconvert($zstrip(fixType, "<>W"), "L"), assumed = ""
    if (action = "FIX_AND_RESEND") && (fixType '= "normalization") && (fixType '= "correction") {
        set assumed = " fixType '" _ fixType _ "' is not normalization or correction: recorded as correction, which needs operator approval."
        set fixType = "correction"
    }
    set incident = ##class(Triage.Data.Incident).%OpenId(incidentId)
    quit:'$isobject(incident) "Rejected: unknown incident " _ incidentId
    quit:incident.AgentAction'="" "Rejected: a decision was already recorded for incident " _ incidentId
    quit:(incident.Status'="NEW")&&(incident.Status'="ANALYZING") "Rejected: incident " _ incidentId _ " was already handled (" _ incident.Status _ "), probably after a timeout"

    set incident.AgentAction = action
    set incident.AgentReason = reason
    set incident.AgentConfidence = confidence
    set incident.AgentPatch = $select($isobject(patch): patch.%ToJSON(), 1: "{}")
    set incident.AgentFixType = $select(action = "FIX_AND_RESEND": fixType, 1: "")
    set incident.UpstreamRecommendation = upstreamRecommendation
    // Not given stays empty: the rules then wait at least MinRetryDelay, never "at once".
    set incident.AgentRetryAfter = $select((action = "RETRY") && (retryAfterSeconds '= ""): +retryAfterSeconds, 1: "")
    set incident.Status = "DECIDED"
    set sc = incident.%Save()
    quit $select(sc: "Decision recorded." _ assumed, 1: "Error: " _ $system.Status.GetErrorText(sc))
}

ClassMethod IsSecret(settingName As %String) As %Boolean
{
    set name = $zconvert(settingName, "L")
    set words = $listfromstring(..#SECRETWORDS)
    for i=1:1:$listlength(words) {
        return:name[$list(words, i) 1
    }
    quit 0
}

}
