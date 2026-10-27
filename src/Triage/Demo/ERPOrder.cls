/// Orders accepted by the fake ERP.
Class Triage.Demo.ERPOrder Extends %Persistent
{

Property OrderId As %String [ Required ];

Property CustomerId As %String;

Property Amount As %Numeric(SCALE = 2);

Property Currency As %String;

Property ShipDate As %String;

Property ReceivedAt As %TimeStamp [ InitialExpression = {$zdatetime($horolog, 3)} ];

Index OrderIdIdx On OrderId [ Unique ];

}
