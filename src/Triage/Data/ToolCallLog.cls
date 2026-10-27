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

}
