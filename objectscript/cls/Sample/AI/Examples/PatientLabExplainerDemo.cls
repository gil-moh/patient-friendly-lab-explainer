Include %occStatus

Class Sample.AI.Examples.PatientLabExplainerDemo Extends %RegisteredObject
{

ClassMethod Demo(patientId As %String = "demo-rich-003", panel As %String = "a1c") As %Status
{
    Try {
        Set narrative = ##class(Sample.AI.Tools.PatientLabExplainer).BuildPatientLabNarrative(patientId, panel)
        Do ..WriteNarrative(narrative)
        Return $$$OK
    } Catch ex {
        Write !, "Patient lab narrative demo failed: ", ex.DisplayString(), !
        Return ex.AsStatus()
    }
}

ClassMethod DemoSynthetic(panel As %String = "a1c") As %Status
{
    Try {
        Set normalized = ##class(Sample.AI.Tools.LabReadOnly).NormalizePanel(panel)
        Set bundle = ##class(Sample.AI.Examples.LabTrendDemo).BuildSyntheticBundle(normalized)
        Set trend = ##class(Sample.AI.Tools.LabTrendEngine).BuildPanelTrendFromBundle("synthetic-patient", normalized, bundle)
        Set narrative = ##class(Sample.AI.Tools.PatientLabExplainer).BuildNarrativeFromTrend("synthetic-patient", normalized, trend)
        Do ..WriteNarrative(narrative)
        Return $$$OK
    } Catch ex {
        Write !, "Patient lab synthetic demo failed: ", ex.DisplayString(), !
        Return ex.AsStatus()
    }
}

ClassMethod DemoToFile(patientId As %String = "demo-rich-003", panel As %String = "a1c", outputPath As %String = "/tmp/patient-lab-explainer.txt", synthetic As %Boolean = 0) As %Status
{
    Set oldIO = $IO
    Set opened = 0

    Try {
        Open outputPath:"NWS":5
        If '$TEST {
            Return $$$ERROR($$$GeneralError, "Unable to open output file: " _ outputPath)
        }

        Set opened = 1
        Use outputPath

        If synthetic {
            Set sc = ..DemoSynthetic(panel)
        } Else {
            Set sc = ..Demo(patientId, panel)
        }

        Use oldIO
        Close outputPath
        Return sc
    } Catch ex {
        If $IO '= oldIO {
            Use oldIO
        }
        If opened {
            Close outputPath
        }
        Return ex.AsStatus()
    }
}

ClassMethod WriteNarrative(narrative As %DynamicObject)
{
    Write !, "Patient-Friendly Lab Explainer", !
    Write "Patient: ", narrative.%Get("patientId"), !
    Set panelLabel = narrative.%Get("panelLabel")
    If panelLabel = "" {
        Set panelLabel = narrative.%Get("panel")
    }
    Write "Panel: ", panelLabel, !

    Set sections = narrative.%Get("sections")
    Do ..WriteSection("Your Most Recent Results", sections)
    Do ..WriteSection("Your Trend", sections)
    Do ..WriteSection("What This Means", sections)
    Do ..WriteSection("Context From Your Medical Record", sections)
    Do ..WriteSection("Careful Lifestyle Options", sections)
    Do ..WriteSection("Questions To Ask Your Doctor", sections)
    Do ..WriteSection("Suggested Next Step", sections)
}

ClassMethod WriteSection(name As %String, sections As %DynamicObject) [ Internal ]
{
    Write !, name, !

    If '$ISOBJECT(sections) {
        Write "- (not available)", !
        Return
    }

    Set lines = sections.%Get(name)
    If '$ISOBJECT(lines) || (lines.%Size()=0) {
        Write "- (not available)", !
        Return
    }

    For i=0:1:(lines.%Size()-1) {
        Set line = lines.%Get(i)
        Write "- ", line, !
    }
}

}
