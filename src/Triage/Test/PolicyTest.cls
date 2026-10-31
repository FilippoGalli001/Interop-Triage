/// Unit tests of the deterministic rules. No production and no LLM are needed.
/// do ##class(%UnitTest.Manager).DebugRunTestCase("", "Triage.Test.PolicyTest", "", "")
Class Triage.Test.PolicyTest Extends %UnitTest.TestCase
{

/// The demo configuration: Currency normalizations are automatic, ids are protected.
Method Config() As %DynamicObject
{
    quit {"minConfidence": 0.7, "maxAttempts": 3, "autoActions": "RETRY,ESCALATE", "autoFixFields": "Currency", "protectedFields": "OrderId,CustomerId"}
}

Method Incident(action As %String, confidence As %Numeric = 0.9, patch As %String = "{}", fixType As %String = "", attempt As %Integer = 1) As Triage.Data.Incident
{
    set incident = ##class(Triage.Data.Incident).%New()
    set incident.MessageClass = "Triage.Demo.OrderRequest"
    set incident.AgentAction = action
    set incident.AgentConfidence = confidence
    set incident.AgentPatch = patch
    set incident.AgentFixType = fixType
    set incident.AttemptNumber = attempt
    quit incident
}

Method AssertVerdict(expected As %String, incident As Triage.Data.Incident, description As %String)
{
    set verdict = ##class(Triage.Policy).Evaluate(incident, ..Config(), .note)
    do $$$AssertEquals(verdict, expected, description _ " [" _ note _ "]")
}

Method TestActions()
{
    do ..AssertVerdict("ESCALATE", ..Incident(""), "empty action")
    do ..AssertVerdict("ESCALATE", ..Incident("REBOOT"), "unknown action")
    do ..AssertVerdict("EXECUTE", ..Incident("ESCALATE", 0.1), "escalation always runs")
    do ..AssertVerdict("EXECUTE", ..Incident("RETRY"), "automatic retry")
    do ..AssertVerdict("APPROVAL", ..Incident("RETRY", 0.5), "low confidence")
    do ..AssertVerdict("ESCALATE", ..Incident("RETRY", 0.9, , , 4), "too many attempts")
    do ..AssertVerdict("APPROVAL", ..Incident("DISCARD"), "discard is not automatic")
}

Method TestFixAutonomy()
{
    do ..AssertVerdict("EXECUTE", ..Incident("FIX_AND_RESEND", 0.9, "{""Currency"":""EUR""}", "normalization"), "normalization of an automatic field")
    do ..AssertVerdict("APPROVAL", ..Incident("FIX_AND_RESEND", 0.9, "{""Currency"":""EUR""}", "correction"), "correction of an automatic field")
    do ..AssertVerdict("APPROVAL", ..Incident("FIX_AND_RESEND", 0.9, "{""ShipDate"":""2026-11-21""}", "normalization"), "field not automatic")
    do ..AssertVerdict("APPROVAL", ..Incident("FIX_AND_RESEND", 0.9, "{""Currency"":""EUR"",""ShipDate"":""2026-11-21""}", "normalization"), "one field not automatic")
}

Method TestFixPatchValidation()
{
    do ..AssertVerdict("ESCALATE", ..Incident("FIX_AND_RESEND", 0.9, "{""OrderId"":""SO-9""}", "correction"), "protected field")
    do ..AssertVerdict("ESCALATE", ..Incident("FIX_AND_RESEND", 0.9, "{""Price"":1}", "correction"), "unknown field")
    do ..AssertVerdict("ESCALATE", ..Incident("FIX_AND_RESEND", 0.9, "{""ShipDate"":{""year"":2026}}", "correction"), "object value")
    do ..AssertVerdict("ESCALATE", ..Incident("FIX_AND_RESEND", 0.9, "{""ShipDate"":[1]}", "correction"), "array value")
    do ..AssertVerdict("ESCALATE", ..Incident("FIX_AND_RESEND", 0.9, "not json", "correction"), "invalid JSON")
    do ..AssertVerdict("ESCALATE", ..Incident("FIX_AND_RESEND", 0.9, "{}", "correction"), "empty patch")
    // An invalid patch is escalated even when the confidence alone would ask for approval.
    do ..AssertVerdict("ESCALATE", ..Incident("FIX_AND_RESEND", 0.3, "{""Price"":1}", "correction"), "invalid patch, low confidence")
}

Method TestOperatorPatch()
{
    set incident = ..Incident("FIX_AND_RESEND", 0.9, "{""ShipDate"":""2026-11-21""}", "correction")
    do $$$AssertEquals(##class(Triage.Policy).CheckPatch(incident, ..Config(), , "{""ShipDate"":""2026-11-22""}"), "", "an operator's patch on a valid field")
    do $$$AssertNotEquals(##class(Triage.Policy).CheckPatch(incident, ..Config(), , "{""OrderId"":""SO-9""}"), "", "an operator's patch cannot change a protected field")
    do $$$AssertNotEquals(##class(Triage.Policy).CheckPatch(incident, ..Config(), , "{""Price"":1}"), "", "an operator's patch cannot add an unknown field")
    do $$$AssertEquals(##class(Triage.Policy).CheckPatch(incident, ..Config(), .patch), "", "without an operator's patch the agent's is checked")
    do $$$AssertEquals(patch.ShipDate, "2026-11-21", "the agent's value")

    set review = "Triage.Service.ReviewService"
    do $$$AssertStatusOK($classmethod(review, "CheckOperatorPatch", incident, 1, "", ""), "approving as proposed needs nothing more")
    do $$$AssertStatusOK($classmethod(review, "CheckOperatorPatch", incident, 1, "day and month were swapped", "{""ShipDate"":""2026-11-22""}"), "a changed patch with a note")
    do $$$AssertStatusNotOK($classmethod(review, "CheckOperatorPatch", incident, 1, " ", "{""ShipDate"":""2026-11-22""}"), "a changed patch without a note")
    do $$$AssertStatusNotOK($classmethod(review, "CheckOperatorPatch", incident, 0, "no", "{""ShipDate"":""2026-11-22""}"), "a patch on a rejection")
    do $$$AssertStatusNotOK($classmethod(review, "CheckOperatorPatch", incident, 1, "why", "{""OrderId"":""SO-9""}"), "a protected field, refused at once")
    do $$$AssertStatusNotOK($classmethod(review, "CheckOperatorPatch", ..Incident("RETRY"), 1, "why", "{""ShipDate"":""2026-11-22""}"), "a patch for a RETRY")
}

/// A model that forgets fixType gets its decision recorded as a correction, not a rejection it would repeat.
Method TestMissingFixType()
{
    set incident = ##class(Triage.Data.Incident).%New()
    set incident.MessageClass = "Triage.Demo.OrderRequest", incident.Status = "ANALYZING"
    do $$$AssertStatusOK(incident.%Save(), "temporary incident")
    set id = incident.%Id()
    set answer = ##class(Triage.Agent.Tools).SubmitDecision(id, "FIX_AND_RESEND", "test", 0.9, {"ShipDate": "2026-11-28"})
    do $$$AssertTrue(answer["Decision recorded", "accepted: " _ answer)
    set incident = ##class(Triage.Data.Incident).%OpenId(id, , .sc)
    do $$$AssertEquals(incident.AgentFixType, "correction", "recorded as correction")
    do $$$AssertEquals(##class(Triage.Policy).Evaluate(incident, ..Config(), .note), "APPROVAL", "so it waits for an operator")
    do ##class(Triage.Data.Incident).%DeleteId(id)
}

Method TestRetryDelay()
{
    set config = {"minRetryDelay": 10, "maxRetryDelay": 3600, "retryStagger": 5}
    do $$$AssertEquals(##class(Triage.Policy).RetryDelay(0, config), 0, "0 resends at once")
    do $$$AssertEquals(##class(Triage.Policy).RetryDelay(60, config), 60, "a delay within limits is kept")
    do $$$AssertEquals(##class(Triage.Policy).RetryDelay(2, config), 10, "too short becomes the minimum")
    do $$$AssertEquals(##class(Triage.Policy).RetryDelay(99999, config), 3600, "too long becomes the maximum")
    do $$$AssertEquals(##class(Triage.Policy).RetryDelay(60, config, 1), 65, "first reuse waits one stagger more")
    do $$$AssertEquals(##class(Triage.Policy).RetryDelay(60, config, 3), 75, "third reuse waits three staggers more")
    do $$$AssertEquals(##class(Triage.Policy).RetryDelay(0, config, 2), 10, "reuses of an immediate retry are still spread out")
    set error = "HTTP 503 Service Unavailable from WMS: scheduled maintenance in progress. Retry-After: 30"
    do $$$AssertEquals(##class(Triage.Policy).RetryDelay("", config), 10, "no request waits the minimum, not 0")
    do $$$AssertEquals(##class(Triage.Policy).RetryDelay("", config, 0, error), 30, "no request honours Retry-After")
    do $$$AssertEquals(##class(Triage.Policy).RetryDelay(0, config, 0, error), 30, "not earlier than Retry-After")
    do $$$AssertEquals(##class(Triage.Policy).RetryDelay(60, config, 0, error), 60, "a longer request is kept")
    do $$$AssertEquals(##class(Triage.Policy).RetryDelay(30, config, 1, error), 35, "staggered after Retry-After")
}

Method TestRetryAfterDate()
{
    set now = "Wed, 28 Oct 2026 10:00:00 GMT"
    set error = "HTTP 503 Service Unavailable from WMS: scheduled maintenance in progress. Retry-After: Wed, 28 Oct 2026 10:02:00 GMT"
    do $$$AssertEquals(##class(Triage.Policy).RetryAfter(error, now), 120, "an HTTP date becomes the seconds left")
    do $$$AssertEquals(##class(Triage.Policy).RetryAfter("Retry-After: Wed, 28 Oct 2026 09:59:00 GMT", now), 0, "a date already past waits nothing")
    do $$$AssertEquals(##class(Triage.Policy).RetryAfter("Retry-After: soon", now), 0, "a value that is not a date is ignored")
    do $$$AssertEquals(##class(Triage.Policy).RetryAfter("Retry-After: 30", now), 30, "seconds still work")
    do $$$AssertEquals(##class(Triage.Policy).RetryAfter("HTTP 503 with no header", now), 0, "no header, no floor")
    set later = "Retry-After: " _ ##class(%SYS.Python).Import("email.utils").formatdate($zdatetime($ztimestamp, -2) + 90, 0, 1)
    set floor = ##class(Triage.Policy).RetryAfter(later)
    do $$$AssertTrue((floor >= 85) && (floor <= 90), "a date 90 s ahead of the clock gives about 90 s (got " _ floor _ ")")
}

Method TestSignature()
{
    set a = ##class(Triage.Data.Incident).Signature("Demo.ERP", "ERROR #6059: socket to erp:8443 failed for order 'SO-1002' after 15 seconds")
    set b = ##class(Triage.Data.Incident).Signature("Demo.ERP", "ERROR #6059: socket to erp:8443 failed for order 'SO-1007' after 15 seconds")
    do $$$AssertEquals(a, b, "ids and numbers do not change the signature")
    do $$$AssertTrue(a["#6059", "the error code is kept: " _ a)
    set c = ##class(Triage.Data.Incident).Signature("Other.Op", "ERROR #6059: socket to erp:8443 failed for order 'SO-1002' after 15 seconds")
    do $$$AssertNotEquals(a, c, "another component has another signature")
}

Method TestScopePolicy()
{
    set scope = ##class(Triage.Agent.ScopePolicy).%New()
    set scope.IncidentId = 7, scope.SessionId = 120
    do $$$AssertStatusOK(scope.%CanExecute("iris:x", {"name": "submit_decision", "arguments": {"incidentId": 7}}, {}), "own incident")
    do $$$AssertStatusNotOK(scope.%CanExecute("iris:x", {"name": "submit_decision", "arguments": {"incidentId": 12}}, {}), "another incident")
    do $$$AssertStatusOK(scope.%CanExecute("iris:x", {"name": "get_event_log", "arguments": {"sessionId": 120}}, {}), "own session")
    do $$$AssertStatusNotOK(scope.%CanExecute("iris:x", {"name": "get_event_log", "arguments": {"sessionId": 300}}, {}), "another session")
    do $$$AssertStatusOK(scope.%CanExecute("iris:x", {"name": "search_runbooks", "arguments": {"query": "timeout"}}, {}), "tools without ids")
}

Method TestReplayRecording()
{
    set a = ##class(Triage.Data.Incident).%New(), b = ##class(Triage.Data.Incident).%New()
    set a.ErrorSignature = "Demo.ERP|HTTP N Conflict: order '?' already exists", a.MessageBody = "{""OrderId"":""SO-1001""}"
    set b.ErrorSignature = a.ErrorSignature, b.MessageBody = a.MessageBody
    do $$$AssertEquals(##class(Triage.Data.Recording).KeyFor(a), ##class(Triage.Data.Recording).KeyFor(b), "same failure, same key in another run")
    set b.MessageBody = "{""OrderId"":""SO-2001""}"
    do $$$AssertNotEquals(##class(Triage.Data.Recording).KeyFor(a), ##class(Triage.Data.Recording).KeyFor(b), "another message, another key")

    // The recorded run was incident 3 in session 40; now it is incident 12 in session 77.
    set recording = ##class(Triage.Data.Recording).%New()
    set recording.Calls = [{"tool": "get_event_log", "arguments": {"sessionId": 40}}, {"tool": "lookup_error_code", "arguments": {"code": "HTTP 409"}}, {"tool": "submit_decision", "arguments": {"incidentId": 3, "action": "DISCARD"}}].%ToJSON()
    set calls = recording.CallsFor(12, 77)
    do $$$AssertEquals(calls.%Get(0).arguments.sessionId, 77, "session id replaced")
    do $$$AssertEquals(calls.%Get(1).arguments.code, "HTTP 409", "other arguments kept")
    do $$$AssertEquals(calls.%Get(2).arguments.incidentId, 12, "incident id replaced")
    do $$$AssertEquals(calls.%Get(2).arguments.action, "DISCARD", "the recorded decision is kept")
}

Method TestOperatorPolicy()
{
    set policy = ##class(Triage.MCP.OperatorPolicy).%New()
    do $$$AssertStatusOK(policy.%CanExecute("iris:x", {"name": "mcp_triage_list_incidents", "arguments": {}}, {}), "reading needs no note")
    do $$$AssertStatusOK(policy.%CanExecute("iris:x", {"name": "mcp_triage_approve_incident", "arguments": {"incidentId": -1, "note": "confirmed"}}, {}), "approval with a note")
    do $$$AssertStatusNotOK(policy.%CanExecute("iris:x", {"name": "mcp_triage_approve_incident", "arguments": {"incidentId": -1, "note": "  "}}, {}), "approval without a note")
    set call = {"name": "resolve_incident"}
    set call.arguments = "{""incidentId"": -1}"
    do $$$AssertStatusNotOK(policy.%CanExecute("iris:x", call, {}), "arguments as a JSON string, without a note")
    &sql(DELETE FROM Triage_Data.ToolCallLog WHERE IncidentId = -1)
}

Method TestToolCallTrace()
{
    set incidentId = -1
    &sql(DELETE FROM Triage_Data.ToolCallLog WHERE IncidentId = :incidentId)
    for call = $listbuild("search_runbooks", "{""query"":""HTTP 503""}", 1, 85), $listbuild("get_event_log", "{""sessionId"":7}", 0, 3), $listbuild("mcp:get_incident", "{""incidentId"":-1}", 1, 40) {
        set log = ##class(Triage.Data.ToolCallLog).%New()
        set log.IncidentId = incidentId, log.ToolName = $list(call, 1), log.Arguments = $list(call, 2), log.Success = $list(call, 3), log.DurationMs = $list(call, 4)
        do log.%Save()
    }
    set trace = ##class(Triage.Data.ToolCallLog).Trace(incidentId)
    do $$$AssertEquals($piece(trace, $char(10), 1), "search_runbooks {""query"":""HTTP 503""} - 85 ms", "a vector search is traced with its query and duration")
    do $$$AssertEquals($piece(trace, $char(10), 2), "get_event_log {""sessionId"":7} - failed", "a failed call says so")
    do $$$AssertEquals($length(trace, $char(10)), 2, "operator calls through MCP are left out")
    &sql(DELETE FROM Triage_Data.ToolCallLog WHERE IncidentId = :incidentId)
}

Method TestAddUsage()
{
    set total = ##class(Triage.Agent.TriageAgent).AddUsage("", {"prompt_tokens": 3000, "completion_tokens": 200, "total_tokens": 3200})
    set total = ##class(Triage.Agent.TriageAgent).AddUsage(total, {"prompt_tokens": 3500, "completion_tokens": 100, "total_tokens": 3600})
    do $$$AssertEquals(total.%Get("prompt_tokens"), 6500, "a reminder adds its prompt tokens")
    do $$$AssertEquals(total.%Get("completion_tokens"), 300, "and its completion tokens")
    do $$$AssertEquals(total.%Get("reasoning_tokens"), "", "a counter no provider reported stays empty")
    do $$$AssertEquals(##class(Triage.Agent.TriageAgent).AddUsage(total, "").%Get("total_tokens"), 6800, "a call without usage changes nothing")
}

Method TestSecretsRedacted()
{
    for name = "Password", "APIToken", "SecretKey", "Credentials" {
        do $$$AssertTrue(##class(Triage.Agent.Tools).IsSecret(name), name _ " is redacted")
    }
    for name = "RetryInterval", "FailureTimeout", "ReplyCodeActions" {
        do $$$AssertNotTrue(##class(Triage.Agent.Tools).IsSecret(name), name _ " is shown")
    }
}

}
