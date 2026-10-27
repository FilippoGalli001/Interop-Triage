/// Demo production: orders flow to a fake ERP; its failures are triaged by the AI agent.
Class Triage.Production.Main Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Triage.Production.Main" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>Orders flow to a fake ERP and stock updates to a fake WMS. Failed messages raise alerts that an AI Hub agent triages.</Description>
  <ActorPoolSize>2</ActorPoolSize>
  <Item Name="Demo.OrderService" Category="Demo" ClassName="Triage.Demo.InboundService" PoolSize="0" Enabled="true">
    <Setting Target="Host" Name="TargetConfigName">Demo.ERP</Setting>
  </Item>
  <Item Name="Demo.StockService" Category="Demo" ClassName="Triage.Demo.InboundService" PoolSize="0" Enabled="true">
    <Setting Target="Host" Name="TargetConfigName">Demo.WMS</Setting>
  </Item>
  <Item Name="Demo.WMS" Category="Demo" ClassName="Triage.Demo.WMSOperation" PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Adapter" Name="HTTPServer">localhost</Setting>
    <Setting Target="Adapter" Name="HTTPPort">52773</Setting>
    <Setting Target="Adapter" Name="URL">/demo/api/wms/movements</Setting>
    <Setting Target="Adapter" Name="Credentials">DemoTargets</Setting>
  </Item>
  <Item Name="Demo.ERP" Category="Demo" ClassName="Triage.Demo.ERPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Adapter" Name="HTTPServer">localhost</Setting>
    <Setting Target="Adapter" Name="HTTPPort">52773</Setting>
    <Setting Target="Adapter" Name="URL">/demo/api/erp/orders</Setting>
    <Setting Target="Adapter" Name="Credentials">DemoTargets</Setting>
    <Setting Target="Adapter" Name="ConnectTimeout">5</Setting>
    <Setting Target="Host" Name="RetryInterval">5</Setting>
    <Setting Target="Host" Name="FailureTimeout">15</Setting>
    <Setting Target="Host" Name="AlertRetryGracePeriod">60</Setting>
  </Item>
  <Item Name="Ens.Alert" Category="Triage" ClassName="Triage.Production.TriageProcess" PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="AutoActions">RETRY,ESCALATE</Setting>
    <Setting Target="Host" Name="AutoFixFields">Currency,Warehouse</Setting>
    <Setting Target="Host" Name="ProtectedFields">OrderId,CustomerId,Sku</Setting>
  </Item>
  <Item Name="Triage.AgentOperation" Category="Triage" ClassName="Triage.Production.AgentOperation" PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="RetryInterval">20</Setting>
    <Setting Target="Host" Name="FailureTimeout">150</Setting>
  </Item>
  <Item Name="Triage.EscalationOperation" Category="Triage" ClassName="Triage.Production.EscalationOperation" PoolSize="1" Enabled="true">
  </Item>
  <Item Name="Ens.Alarm" Category="Triage" ClassName="Ens.Alarm" PoolSize="1" Enabled="true">
  </Item>
  <Item Name="Triage.ReviewService" Category="Triage" ClassName="Triage.Service.ReviewService" PoolSize="0" Enabled="true">
  </Item>
</Production>
}

}
