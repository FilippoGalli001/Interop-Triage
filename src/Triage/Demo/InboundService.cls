/// Entry point of the demo messages: forwards each message to its target operation.
/// Used twice in the demo production: orders to the ERP and stock updates to the WMS.
Class Triage.Demo.InboundService Extends Ens.BusinessService
{

Property TargetConfigName As Ens.DataType.ConfigName;

Parameter SETTINGS = "TargetConfigName:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId}";

Method OnProcessInput(pInput As Ens.Request, Output pOutput As %RegisteredObject) As %Status
{
    quit ..SendRequestAsync(..TargetConfigName, pInput)
}

}
