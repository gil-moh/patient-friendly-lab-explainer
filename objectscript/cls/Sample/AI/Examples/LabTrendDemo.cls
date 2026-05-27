Include %occStatus

Class Sample.AI.Examples.LabTrendDemo Extends %RegisteredObject
{

/// Demo for Phase 2: deterministic lab trend payload.
ClassMethod Demo(patientId As %String = "demo-rich-003", panel As %String = "a1c") As %Status
{
    Try {
        Set out = ##class(Sample.AI.Tools.LabTrendEngine).BuildPanelTrend(patientId, panel, 300)

        Write !, "Lab Trend Demo", !
        Write "patientId=", patientId, !
        Write "panel=", panel, !
        If $ISOBJECT(out) {
            Write out.%ToJSON(), !
        }

        Return $$$OK
    } Catch ex {
        Write !, "Lab trend demo failed: ", ex.DisplayString(), !
        Return ex.AsStatus()
    }
}

/// Synthetic fixture demo to validate trend logic when live server lacks panel data.
ClassMethod DemoSynthetic(panel As %String = "a1c") As %Status
{
    Try {
        Set normalized = ##class(Sample.AI.Tools.LabReadOnly).NormalizePanel(panel)
        Set bundle = ..BuildSyntheticBundle(normalized)
        Set out = ##class(Sample.AI.Tools.LabTrendEngine).BuildPanelTrendFromBundle("synthetic-patient", normalized, bundle)

        Write !, "Lab Trend Synthetic Demo", !
        Write "panel=", normalized, !
        Write out.%ToJSON(), !
        Return $$$OK
    } Catch ex {
        Write !, "Lab trend synthetic demo failed: ", ex.DisplayString(), !
        Return ex.AsStatus()
    }
}

ClassMethod BuildSyntheticBundle(panel As %String) As %DynamicObject [ Internal ]
{
    Set bundle = {}
    Set bundle.resourceType = "Bundle"
    Set bundle.type = "searchset"
    Set bundle.entry = []

    If panel = "a1c" {
        Do bundle.entry.%Push(..Entry("a1c-new", "4548-4", "Hemoglobin A1c", 8.1, "%", "2026-05-01"))
        Do bundle.entry.%Push(..Entry("a1c-old", "4548-4", "Hemoglobin A1c", 7.4, "%", "2026-02-01"))
        Return bundle
    }

    If panel = "lipids" {
        Do bundle.entry.%Push(..Entry("ldl-new", "13457-7", "LDL cholesterol", 148, "mg/dL", "2026-05-01"))
        Do bundle.entry.%Push(..Entry("ldl-old", "13457-7", "LDL cholesterol", 130, "mg/dL", "2026-02-01"))
        Do bundle.entry.%Push(..Entry("hdl-new", "2085-9", "HDL cholesterol", 37, "mg/dL", "2026-05-01"))
        Do bundle.entry.%Push(..Entry("hdl-old", "2085-9", "HDL cholesterol", 42, "mg/dL", "2026-02-01"))
        Return bundle
    }

    // Fallback synthetic CMP sample.
    Do bundle.entry.%Push(..Entry("cr-new", "2160-0", "Creatinine", 1.4, "mg/dL", "2026-05-01"))
    Do bundle.entry.%Push(..Entry("cr-old", "2160-0", "Creatinine", 1.2, "mg/dL", "2026-02-01"))
    Return bundle
}

ClassMethod Entry(id As %String, loinc As %String, display As %String, value As %Double, unit As %String, effective As %String) As %DynamicObject [ Internal ]
{
    Set coding = {}
    Set coding.system = "http://loinc.org"
    Set coding.code = loinc
    Set coding.display = display

    Set codeObj = {}
    Set codeObj.text = display
    Set codeObj.coding = []
    Do codeObj.coding.%Push(coding)

    Set valueQuantity = {}
    Set valueQuantity.value = value
    Set valueQuantity.unit = unit

    Set obs = {}
    Set obs.resourceType = "Observation"
    Set obs.id = id
    Set obs.code = codeObj
    Set obs.valueQuantity = valueQuantity
    Set obs.effectiveDateTime = effective

    Set entry = {}
    Set entry.resource = obs
    Return entry
}

}
