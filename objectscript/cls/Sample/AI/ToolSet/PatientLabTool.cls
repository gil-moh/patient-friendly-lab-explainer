/// Patient-facing lab explainer toolset.
Class Sample.AI.ToolSet.PatientLabTool Extends %AI.ToolSet
    [ DependsOn = Sample.AI.Tools.PatientLabTool ]
{

XData Definition [ MimeType = application/xml ]
{
  <ToolSet Name="PatientLabTool">
    <Description>
      Patient-friendly explanations for lab panels with deterministic sections,
      trend interpretation, and grounded educational snippets.
    </Description>

    <Policies>
      <Audit Class="%AI.Policy.ConsoleAudit"/>
    </Policies>

    <Include Class="Sample.AI.Tools.PatientLabTool" Match="^(Explain)"/>
  </ToolSet>
}

}
