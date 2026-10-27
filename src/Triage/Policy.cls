/// Deterministic rules that decide whether an agent decision is executed, sent for approval or escalated.
/// Invalid decisions are escalated, risky or uncertain ones wait for an operator, safe ones run.
Class Triage.Policy
{

Parameter ACTIONS = "RETRY,FIX_AND_RESEND,DISCARD,ESCALATE";

/// Returns EXECUTE, APPROVAL or ESCALATE. note says why the decision is not executed as is.
/// For FIX_AND_RESEND, patch returns the validated patch.
/// config: minConfidence, maxAttempts, autoActions, autoFixFields, protectedFields (comma-separated lists).
ClassMethod Evaluate(incident As Triage.Data.Incident, config As %DynamicObject, Output note As %String, Output patch As %DynamicObject) As %String
{
    set note = "", patch = ""
    set action = incident.AgentAction
    if '..InList(..#ACTIONS, action) {
        set note = "Unknown action '" _ action _ "'"
        quit "ESCALATE"
    }
    quit:action="ESCALATE" "EXECUTE"

    if (action '= "DISCARD") && (incident.AttemptNumber > config.maxAttempts) {
        set note = "Attempt " _ incident.AttemptNumber _ " exceeds the maximum of " _ config.maxAttempts
        quit "ESCALATE"
    }
    if action = "FIX_AND_RESEND" {
        set note = ..CheckPatch(incident, config, .patch)
        quit:note'="" "ESCALATE"
    }
    if incident.AgentConfidence < config.minConfidence {
        set note = "Confidence " _ incident.AgentConfidence _ " below " _ config.minConfidence _ ": needs approval"
        quit "APPROVAL"
    }
    quit:..InList(config.autoActions, action) "EXECUTE"
    if (action = "FIX_AND_RESEND") && (incident.AgentFixType = "normalization") && ..AllInList(config.autoFixFields, patch) {
        quit "EXECUTE"
    }
    set note = action _ " is not automatic" _ $select(action = "FIX_AND_RESEND": " for these fields", 1: "") _ ": needs approval"
    quit "APPROVAL"
}

/// Seconds to wait before a RETRY. The agent's request is kept within minRetryDelay..maxRetryDelay
/// (0 stays 0: resend at once; no request at all waits minRetryDelay). A Retry-After the target sent
/// in the error is a floor: the agent cannot resend earlier, even if it forgets to ask.
/// Incidents that reuse one decision are spread out by retryStagger seconds each, so a recovering
/// target does not receive the whole backlog at the same instant.
/// position: 0 for the incident the agent decided, 1, 2... for the incidents that reused its decision.
ClassMethod RetryDelay(requested As %Integer, config As %DynamicObject, position As %Integer = 0, errorText As %String = "") As %Integer
{
    set delay = $select(requested = "": config.minRetryDelay, 1: +requested)
    set floor = ..RetryAfter(errorText)
    set:floor>delay delay = floor
    if delay > 0 {
        set delay = $select(delay < config.minRetryDelay: config.minRetryDelay, delay > config.maxRetryDelay: config.maxRetryDelay, 1: delay)
    }
    quit:delay=0&&(position=0) 0
    quit delay + (position * config.retryStagger)
}

/// The seconds of a "Retry-After: N" in an error text, 0 when there is none.
ClassMethod RetryAfter(errorText As %String) As %Integer
{
    set at = $find($zconvert(errorText, "L"), "retry-after:")
    quit:'at 0
    quit +$zstrip($extract(errorText, at, at + 10), "<W")
}

/// Returns "" when the patch of a FIX_AND_RESEND may be applied to the failed message, otherwise why not.
/// json is the patch to check: the agent's by default, or one an operator wrote instead.
ClassMethod CheckPatch(incident As Triage.Data.Incident, config As %DynamicObject, Output patch As %DynamicObject, json As %String = "") As %String
{
    set patch = ""
    set:json="" json = incident.AgentPatch
    try {
        set patch = ##class(%DynamicObject).%FromJSON(json)
    } catch {
    }
    quit:'$isobject(patch) "The patch is not a JSON object"
    quit:patch.%Size()=0 "FIX_AND_RESEND without any field to change"

    set allowed = ##class(Triage.Util).PropertyNames(incident.MessageClass)
    set iter = patch.%GetIterator()
    set problem = ""
    while iter.%GetNext(.field, .value) {
        if '$listfind(allowed, field) {
            set problem = "The patch changes unknown field " _ field
        } elseif ..InList(config.protectedFields, field) {
            set problem = "The patch changes protected field " _ field
        } elseif '$listfind($listbuild("string", "number", "boolean"), patch.%GetTypeOf(field)) {
            set problem = "The patch gives field " _ field _ " a " _ patch.%GetTypeOf(field) _ " instead of a single value"
        }
        quit:problem'=""
    }
    quit problem
}

ClassMethod InList(list As %String, item As %String) As %Boolean
{
    quit:item="" 0
    quit ''$listfind($listfromstring($zstrip(list, "*W")), item)
}

/// True when every field of the patch is in the comma-separated list.
ClassMethod AllInList(list As %String, patch As %DynamicObject) As %Boolean
{
    set iter = patch.%GetIterator()
    set all = 1
    while iter.%GetNext(.field) {
        if '..InList(list, field) {
            set all = 0
            quit
        }
    }
    quit all
}

}
