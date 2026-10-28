/// One tool call made by the triage agent.
Class Triage.Data.ToolCallLog Extends %Persistent
{

Property IncidentId As %Integer;

Property Timestamp As %TimeStamp [ InitialExpression = {$zdatetime($horolog, 3)} ];

Property ToolName As %String(MAXLEN = 256);

Property Arguments As %String(MAXLEN = "");

Property Success As %Boolean;

Property DurationMs As %Integer;

Property ResultPreview As %String(MAXLEN = 1000);

Property Error As %String(MAXLEN = "");

Index IncidentIdx On IncidentId;

/// The agent's tool calls for an incident, one per line: "name {arguments} - N ms" ("- failed" on error).
/// Operator calls made through MCP ("mcp:...") are left out.
ClassMethod Trace(incidentId As %Integer) As %String
{
    set lines = ""
    set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ToolName, Arguments, Success, DurationMs FROM Triage_Data.ToolCallLog WHERE IncidentId = ? AND NOT (ToolName %STARTSWITH 'mcp:') ORDER BY %ID", incidentId)
    while rs.%Next() {
        set args = rs.Arguments
        set:$length(args)>200 args = $extract(args, 1, 197) _ "..."
        set line = rs.ToolName _ " " _ args _ " - " _ $select(rs.Success: +rs.DurationMs _ " ms", 1: "failed")
        set lines = lines _ $select(lines = "": "", 1: $char(10)) _ line
    }
    quit lines
}

}
