/// The tool calls an LLM made for one kind of failure, recorded from a live run.
/// In replay mode (no LLM key) the agent repeats these calls instead of asking the LLM: the tools,
/// the policies, the rules, the delayed retries and the approvals all run for real on the current data.
Class Triage.Data.Recording Extends %Persistent
{

/// Error signature plus message body: the same scenario gives the same key in every run.
Property RecordingKey As %String(MAXLEN = 64) [ Required ];

Property Provider As %String(MAXLEN = 128);

Property Model As %String(MAXLEN = 256);

Property RecordedAt As %TimeStamp;

Property SourceConfigName As %String(MAXLEN = 256);

Property AlertText As %String(MAXLEN = "");

Property MessageBody As %String(MAXLEN = "");

/// JSON array of {"tool": name, "arguments": {...}}, in the order the LLM called them.
Property Calls As %String(MAXLEN = "");

Property PromptTokens As %Integer;

Property CompletionTokens As %Integer;

Index KeyIdx On RecordingKey [ Unique ];

ClassMethod KeyFor(incident As Triage.Data.Incident) As %String
{
    quit $system.Encryption.Base64Encode($system.Encryption.SHA1Hash(incident.ErrorSignature _ "|" _ incident.MessageBody))
}

/// Saves (or replaces) the recording of a live agent run, from its tool call log.
ClassMethod Record(incident As Triage.Data.Incident) As %Status
{
    set calls = []
    set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ToolName, Arguments FROM Triage_Data.ToolCallLog WHERE IncidentId = ? AND Success = 1 ORDER BY %ID", incident.%Id())
    while rs.%Next() {
        set args = {}
        try {
            set args = ##class(%DynamicObject).%FromJSON(rs.Arguments)
        } catch {
        }
        do calls.%Push({"tool": ($zconvert(rs.ToolName, "L")), "arguments": (args)})
    }
    quit:calls.%Size()=0 $$$OK
    set key = ..KeyFor(incident)
    set recording = ..KeyIdxOpen(key)
    set:'$isobject(recording) recording = ..%New()
    set recording.RecordingKey = key
    set recording.Provider = ##class(Triage.Util).Env("LLM_PROVIDER")
    set recording.Model = incident.Model
    set recording.RecordedAt = $zdatetime($horolog, 3)
    set recording.SourceConfigName = incident.SourceConfigName
    set recording.AlertText = incident.AlertText
    set recording.MessageBody = incident.MessageBody
    set recording.Calls = calls.%ToJSON()
    set recording.PromptTokens = incident.PromptTokens
    set recording.CompletionTokens = incident.CompletionTokens
    quit recording.%Save()
}

/// The recorded calls with the ids of the recorded run replaced by those of the current incident.
Method CallsFor(incidentId As %Integer, sessionId As %Integer) As %DynamicArray
{
    set calls = ##class(%DynamicArray).%FromJSON(..Calls)
    set iter = calls.%GetIterator()
    while iter.%GetNext(, .call) {
        set args = call.arguments
        set:args.%IsDefined("incidentId") args.incidentId = +incidentId
        set:args.%IsDefined("sessionId") args.sessionId = +sessionId
    }
    quit calls
}

/// Writes every recording to a JSON file (shipped in the repository for replay mode).
ClassMethod Export(path As %String) As %Status
{
    set all = []
    set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT %ID FROM Triage_Data.Recording ORDER BY SourceConfigName, %ID")
    while rs.%Next() {
        set r = ..%OpenId(rs.ID)
        do all.%Push({"key": (r.RecordingKey), "provider": (r.Provider), "model": (r.Model), "recordedAt": (r.RecordedAt),
            "component": (r.SourceConfigName), "alertText": (r.AlertText), "messageBody": (r.MessageBody),
            "promptTokens": (r.PromptTokens), "completionTokens": (r.CompletionTokens), "calls": (##class(%DynamicArray).%FromJSON(r.Calls))})
    }
    set file = ##class(%Stream.FileCharacter).%New()
    set file.TranslateTable = "UTF8"
    set sc = file.LinkToFile(path)
    quit:$$$ISERR(sc) sc
    do all.%ToJSON(file)
    quit file.%Save()
}

/// Loads the recordings of a file written by Export, replacing those with the same key.
ClassMethod Import(path As %String) As %Status
{
    quit:'##class(%File).Exists(path) $$$OK
    set file = ##class(%Stream.FileCharacter).%New()
    set file.TranslateTable = "UTF8"
    set sc = file.LinkToFile(path)
    quit:$$$ISERR(sc) sc
    set all = ##class(%DynamicArray).%FromJSON(file)
    set iter = all.%GetIterator()
    while iter.%GetNext(, .item) {
        set r = ..KeyIdxOpen(item.key)
        set:'$isobject(r) r = ..%New()
        set r.RecordingKey = item.key, r.Provider = item.provider, r.Model = item.model, r.RecordedAt = item.recordedAt
        set r.SourceConfigName = item.component, r.AlertText = item.alertText, r.MessageBody = item.messageBody
        set r.PromptTokens = item.promptTokens, r.CompletionTokens = item.completionTokens, r.Calls = item.calls.%ToJSON()
        set sc = r.%Save()
        quit:$$$ISERR(sc)
    }
    quit sc
}

}
