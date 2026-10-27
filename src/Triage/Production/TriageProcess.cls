/// Receives the alerts of failing components (configure it with the name Ens.Alert), asks the
/// agent for a decision, applies the deterministic rules of Triage.Policy and executes the result.
/// Also receives the operators' answers (Triage.Msg.ReviewRequest) for decisions waiting for approval.
Class Triage.Production.TriageProcess Extends Ens.BusinessProcess
{

/// Below this confidence, a decision waits for approval.
Property MinConfidence As %Numeric [ InitialExpression = 0.7 ];

/// Highest attempt number for which the message may still be resent.
Property MaxAttempts As %Integer [ InitialExpression = 3 ];

/// Actions executed without approval. ESCALATE is always executed.
Property AutoActions As %String [ InitialExpression = "RETRY,ESCALATE" ];

/// Fields whose normalization (same value, canonical form) is applied without approval.
Property AutoFixFields As %String(MAXLEN = 1000);

/// Fields the agent may never change, not even with approval (identifiers, keys).
Property ProtectedFields As %String(MAXLEN = 1000);

/// Seconds during which alerts with the same error signature reuse the first decision.
Property CoalesceWindow As %Integer [ InitialExpression = 120 ];

/// Most agent runs per minute; beyond it incidents are escalated without calling the LLM.
Property MaxAgentRunsPerMinute As %Integer [ InitialExpression = 10 ];

/// Shortest and longest wait the agent may ask before a RETRY, in seconds.
Property MinRetryDelay As %Integer [ InitialExpression = 10 ];

Property MaxRetryDelay As %Integer [ InitialExpression = 3600 ];

/// Extra seconds between the resends of incidents that reuse one RETRY decision.
Property RetryStagger As %Integer [ InitialExpression = 5 ];

/// Seconds to wait for the agent before escalating.
Property AgentTimeout As %Integer [ InitialExpression = 180 ];

Property AgentTarget As Ens.DataType.ConfigName [ InitialExpression = "Triage.AgentOperation" ];

Property EscalationTarget As Ens.DataType.ConfigName [ InitialExpression = "Triage.EscalationOperation" ];

Parameter SETTINGS = "AutoActions:Autonomy,AutoFixFields:Autonomy,ProtectedFields:Autonomy,MinConfidence:Autonomy,MaxAttempts:Autonomy,MinRetryDelay:Retry,MaxRetryDelay:Retry,RetryStagger:Retry,CoalesceWindow:Cost,MaxAgentRunsPerMinute:Cost,AgentTimeout:Cost,AgentTarget:Triage:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},EscalationTarget:Triage:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId}";

Method OnRequest(pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status
{
    quit:pRequest.%IsA("Triage.Msg.ReviewRequest") ..OnReview(pRequest)
    quit:'pRequest.%IsA("Ens.AlertRequest") $$$ERROR($$$GeneralError, "Unexpected request " _ $classname(pRequest))

    // The triage components never triage themselves.
    if $extract(pRequest.SourceConfigName, 1, 7) = "Triage." {
        $$$LOGWARNING("Ignoring alert from triage component " _ pRequest.SourceConfigName _ ": " _ pRequest.AlertText)
        quit $$$OK
    }
    set sc = ##class(Triage.Data.Incident).CreateFromAlert(pRequest, .incident)
    quit:$$$ISERR(sc) sc
    quit:incident.FailedHeaderId="" ..Escalate(incident, "The failed message could not be found")

    // One analysis per error signature at a time: an identical alert waits for the first decision
    // and reuses it. With PoolSize=1 alerts are serialized anyway; the lock keeps it true with more jobs.
    set lockKey = $zcrc(incident.ErrorSignature, 7)
    lock +^Triage.SignatureLock(lockKey):(..AgentTimeout + 10)
    set locked = $test
    set sc = ..Analyze(incident)
    lock:locked -^Triage.SignatureLock(lockKey)
    quit:$$$ISERR(sc) sc
    quit:incident.FinalAction'="" $$$OK

    quit ..Decide(incident)
}

/// Gets a decision for the incident: reused from an open incident with the same error, or from the agent.
/// When the agent cannot answer, the incident is escalated (FinalAction is then set).
Method Analyze(incident As Triage.Data.Incident) As %Status
{
    quit:..ReuseLeaderDecision(incident) $$$OK
    if ..AgentRunsLastMinute() >= ..MaxAgentRunsPerMinute {
        quit ..Escalate(incident, "Agent budget of " _ ..MaxAgentRunsPerMinute _ " runs per minute reached")
    }
    // Shown on the dashboard while the LLM works.
    set incident.Status = "ANALYZING"
    do incident.%Save()
    set request = ##class(Triage.Msg.TriageRequest).%New()
    set request.IncidentId = incident.%Id()
    set sc = ..SendRequestSync(..AgentTarget, request, .decision, ..AgentTimeout)
    // The agent operation saved its decision on the incident: discard our stale copy.
    do incident.%Reload()
    if $$$ISERR(sc) || '$isobject(decision) {
        quit ..Escalate(incident, "Agent unavailable: " _ $select($$$ISERR(sc): $system.Status.GetErrorText(sc), 1: "no response"))
    }
    quit $$$OK
}

/// Applies the rules to the decision and executes it, asks for approval or escalates.
Method Decide(incident As Triage.Data.Incident) As %Status
{
    set verdict = ##class(Triage.Policy).Evaluate(incident, ..PolicyConfig(), .note, .patch)
    quit:verdict="ESCALATE" ..Escalate(incident, note)
    if verdict = "APPROVAL" {
        set incident.Status = "PENDING_APPROVAL"
        set incident.GuardrailNote = note
        $$$LOGWARNING("Incident " _ incident.%Id() _ " waits for approval: " _ incident.AgentAction _ " " _ incident.AgentPatch _ " (" _ note _ ")")
        quit incident.%Save()
    }
    quit ..Execute(incident, patch)
}

/// Executes or rejects a decision that was waiting for approval.
Method OnReview(review As Triage.Msg.ReviewRequest) As %Status
{
    set incident = ##class(Triage.Data.Incident).%OpenId(review.IncidentId)
    quit:'$isobject(incident) $$$ERROR($$$GeneralError, "Unknown incident " _ review.IncidentId)
    quit:incident.Status'="PENDING_APPROVAL" $$$ERROR($$$GeneralError, "Incident " _ review.IncidentId _ " is not waiting for approval")

    set incident.ReviewedBy = review.Operator
    set incident.ReviewedAt = $zdatetime($horolog, 3)
    set incident.ReviewNote = review.Note
    if 'review.Approved {
        set incident.Status = "REJECTED"
        set incident.FinalAction = "ESCALATE"
        $$$LOGINFO("Incident " _ incident.%Id() _ ": " _ incident.AgentAction _ " rejected by " _ review.Operator _ ". " _ review.Note)
        set sc = incident.%Save()
    } else {
        // The patch is checked again: the configuration may have changed since the proposal.
        // An operator's patch replaces the agent's and passes the same rules.
        set patch = "", problem = ""
        if incident.AgentAction = "FIX_AND_RESEND" {
            set incident.OperatorPatch = review.Patch
            set problem = ##class(Triage.Policy).CheckPatch(incident, ..PolicyConfig(), .patch, review.Patch)
        }
        if problem '= "" {
            set sc = ..Escalate(incident, problem)
        } else {
            $$$LOGINFO("Incident " _ incident.%Id() _ ": " _ incident.AgentAction _ " approved by " _ review.Operator _ $select(review.Patch'="": " with patch " _ review.Patch, 1: ""))
            set sc = ..Execute(incident, patch)
        }
    }
    quit:$$$ISERR(sc) sc
    // What the operator decided is remembered for similar incidents.
    set sc = ##class(Triage.Knowledge.Base).RememberIncident(incident)
    if $$$ISERR(sc) { $$$LOGSTATUS(sc) }
    quit $$$OK
}

/// Runs an allowed decision: resend, patched resend, discard or escalation.
Method Execute(incident As Triage.Data.Incident, patch As %DynamicObject = "") As %Status
{
    set action = incident.AgentAction
    set incident.FinalAction = action
    if action = "DISCARD" {
        set incident.Status = "DISCARDED"
        $$$LOGINFO("Incident " _ incident.%Id() _ " discarded: " _ incident.AgentReason)
        quit incident.%Save()
    }
    quit:action="ESCALATE" ..Escalate(incident, "")
    if action = "RETRY" {
        set incident.RetryDelay = ##class(Triage.Policy).RetryDelay(incident.AgentRetryAfter, ..PolicyConfig(), ..PositionInGroup(incident), incident.AlertText)
        quit:incident.RetryDelay>0 ..ScheduleRetry(incident)
    }
    quit ..Resend(incident, patch)
}

/// Waits RetryDelay seconds out of band: the operation's queue is free meanwhile, and Ens.Alarm wakes
/// this process up in OnResponse, in the same session of the Visual Trace.
Method ScheduleRetry(incident As Triage.Data.Incident) As %Status
{
    set incident.Status = "SCHEDULED_RETRY"
    set sc = incident.%Save()
    quit:$$$ISERR(sc) sc
    set alarm = ##class(Ens.AlarmRequest).%New()
    set alarm.Timeout = incident.RetryDelay
    $$$LOGINFO("Incident " _ incident.%Id() _ ": RETRY in " _ incident.RetryDelay _ " s")
    quit ..SendRequestAsync("Ens.Alarm", alarm, 1, "RETRY:" _ incident.%Id(), "Delayed retry of incident " _ incident.%Id())
}

/// Ens.Alarm answers when a scheduled retry is due.
Method OnResponse(request As Ens.Request, ByRef response As Ens.Response, callrequest As Ens.Request, callresponse As Ens.Response, pCompletionKey As %String) As %Status
{
    quit:$piece(pCompletionKey, ":")'="RETRY" $$$OK
    set incident = ##class(Triage.Data.Incident).%OpenId($piece(pCompletionKey, ":", 2))
    quit:'$isobject(incident) $$$OK
    // An operator may have handled it while it was waiting.
    quit:incident.Status'="SCHEDULED_RETRY" $$$OK
    quit ..Resend(incident, "")
}

/// 0 for an incident the agent decided, n for the n-th incident that reused its decision.
Method PositionInGroup(incident As Triage.Data.Incident) As %Integer
{
    quit:incident.LeaderIncidentId="" 0
    set position = 0
    &sql(SELECT COUNT(*) INTO :position FROM Triage_Data.Incident
         WHERE LeaderIncidentId = :incident.LeaderIncidentId AND %ID <= :incident.%Id())
    quit position
}

/// Copies the decision of a recent incident with the same error signature, when that decision
/// does not depend on the single message (RETRY or ESCALATE) and the incident is still open.
/// Once an operator resolved it, the same error again is news: the agent looks at it. Returns 1 when it did.
Method ReuseLeaderDecision(incident As Triage.Data.Incident) As %Boolean
{
    set since = $system.SQL.Functions.DATEADD("ss", -..CoalesceWindow, $zdatetime($horolog, 3))
    set leaderId = ""
    &sql(SELECT TOP 1 %ID INTO :leaderId FROM Triage_Data.Incident
         WHERE ErrorSignature = :incident.ErrorSignature AND %ID <> :incident.%Id()
           AND LeaderIncidentId IS NULL AND CreatedAt >= :since
           AND FinalAction IN ('RETRY', 'ESCALATE') AND Status IN ('SCHEDULED_RETRY', 'RESENT', 'ESCALATED')
         ORDER BY %ID DESC)
    quit:SQLCODE'=0 0

    set leader = ##class(Triage.Data.Incident).%OpenId(leaderId)
    set incident.LeaderIncidentId = leaderId
    set incident.AgentAction = leader.FinalAction
    set incident.AgentConfidence = leader.AgentConfidence
    set incident.AgentRetryAfter = leader.AgentRetryAfter
    set incident.AgentReason = "Same error as incident " _ leaderId _ " (" _ leader.FinalAction _ "): " _ leader.AgentReason
    set incident.Status = "DECIDED"
    do incident.%Save()
    $$$LOGINFO("Incident " _ incident.%Id() _ " reuses the decision of incident " _ leaderId _ " without calling the agent")
    quit 1
}

Method AgentRunsLastMinute() As %Integer
{
    set since = $system.SQL.Functions.DATEADD("ss", -60, $zdatetime($horolog, 3))
    set runs = 0
    &sql(SELECT COUNT(*) INTO :runs FROM Triage_Data.Incident
         WHERE CreatedAt >= :since AND Model IS NOT NULL)
    quit runs
}

Method PolicyConfig() As %DynamicObject
{
    quit {
        "minConfidence": (..MinConfidence),
        "maxAttempts": (..MaxAttempts),
        "autoActions": (..AutoActions),
        "autoFixFields": (..AutoFixFields),
        "protectedFields": (..ProtectedFields),
        "minRetryDelay": (..MinRetryDelay),
        "maxRetryDelay": (..MaxRetryDelay),
        "retryStagger": (..RetryStagger)
    }
}

/// Resends the failed message to its original target, with the patch applied if there is one.
Method Resend(incident As Triage.Data.Incident, patch As %DynamicObject = "") As %Status
{
    set body = ""
    if $isobject(patch) {
        set original = $classmethod(incident.MessageClass, "%OpenId", incident.MessageBodyId)
        set body = original.%ConstructClone()
        set iter = patch.%GetIterator()
        while iter.%GetNext(.field, .value) {
            set $property(body, field) = value
        }
        set sc = body.%Save()
        quit:$$$ISERR(sc) ..Escalate(incident, "Patched message could not be saved: " _ $system.Status.GetErrorText(sc))
    }
    set sc = ##class(Ens.MessageHeader).ResendDuplicatedMessage(incident.FailedHeaderId, .newHeaderId, "", body)
    quit:$$$ISERR(sc) ..Escalate(incident, "Resend failed: " _ $system.Status.GetErrorText(sc))

    set ^Triage.Resend(newHeaderId) = incident.RootHeaderId
    set incident.ResendHeaderId = newHeaderId
    set incident.Status = "RESENT"
    $$$LOGINFO("Incident " _ incident.%Id() _ ": " _ incident.FinalAction _ " as message " _ newHeaderId)
    quit incident.%Save()
}

/// Hands the incident to the escalation target. note says why the rules escalated it.
Method Escalate(incident As Triage.Data.Incident, note As %String) As %Status
{
    set incident.FinalAction = "ESCALATE"
    set incident.GuardrailNote = note
    set sc = incident.%Save()
    quit:$$$ISERR(sc) sc
    set request = ##class(Triage.Msg.EscalationRequest).%New()
    set request.IncidentId = incident.%Id()
    quit ..SendRequestAsync(..EscalationTarget, request, 0)
}

}
