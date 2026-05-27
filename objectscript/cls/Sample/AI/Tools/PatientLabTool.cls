Include %occStatus

Class Sample.AI.Tools.PatientLabTool Extends %AI.Tool
{

/// End-to-end patient-friendly explanation payload for one lab panel.
Method ExplainLabPanel(patientId As %String, panel As %String = "a1c") As %DynamicObject
{
    If patientId = "" {
        Return {"error":"patientId is required"}
    }

    Set normalized = ##class(Sample.AI.Tools.LabReadOnly).NormalizePanel(panel)
    Set narrative = ##class(Sample.AI.Tools.PatientLabExplainer).BuildPatientLabNarrative(patientId, normalized)
    Return narrative
}

/// Deterministic synthetic explanation payload for validation and demos.
Method ExplainLabPanelSynthetic(panel As %String = "a1c") As %DynamicObject
{
    Set normalized = ##class(Sample.AI.Tools.LabReadOnly).NormalizePanel(panel)
    Set bundle = ##class(Sample.AI.Examples.LabTrendDemo).BuildSyntheticBundle(normalized)
    Set trend = ##class(Sample.AI.Tools.LabTrendEngine).BuildPanelTrendFromBundle("synthetic-patient", normalized, bundle)
    Set narrative = ##class(Sample.AI.Tools.PatientLabExplainer).BuildNarrativeFromTrend("synthetic-patient", normalized, trend)
    Return narrative
}

}
