/// Stock movements accepted by the fake WMS.
Class Triage.Demo.WMSMovement Extends %Persistent
{

Property Sku As %String [ Required ];

Property Warehouse As %String;

Property Quantity As %Integer;

Property Unit As %String;

Property ReceivedAt As %TimeStamp [ InitialExpression = {$zdatetime($horolog, 3)} ];

}
