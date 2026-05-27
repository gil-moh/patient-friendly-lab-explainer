Include %occStatus

Class Sample.AI.Examples.PatientLabQualityChecks Extends %RegisteredObject
{

ClassMethod RunSyntheticChecks() As %Status
{
    Set failures = 0

    Try {
        Write !, "Patient Lab Quality Checks", !

        Set tool = ##class(Sample.AI.Tools.PatientLabTool).%New()

        Set p1 = tool.ExplainLabPanelSynthetic("a1c")
        Do ..CheckNarrativeContract(p1, "a1c", .failures)

        // Determinism check: same synthetic input should produce identical payload.
        Set p2 = tool.ExplainLabPanelSynthetic("a1c")
        Do p1.%Set("generatedAt", "")
        Do p2.%Set("generatedAt", "")
        Set j1 = p1.%ToJSON()
        Set j2 = p2.%ToJSON()
        If j1 '= j2 {
            Do ..Fail("Determinism check failed for synthetic a1c payload", .failures)
        } Else {
            Do ..Pass("Determinism check passed for synthetic a1c payload")
        }

        Set p3 = tool.ExplainLabPanelSynthetic("lipids")
        Do ..CheckNarrativeContract(p3, "lipids", .failures)

        If failures > 0 {
            Write !, "QUALITY_CHECKS=FAILED count=", failures, !
            Return $$$ERROR($$$GeneralError, "Quality checks failed")
        }

        Write !, "QUALITY_CHECKS=OK", !
        Return $$$OK
    } Catch ex {
        Write !, "Quality check run failed: ", ex.DisplayString(), !
        Return ex.AsStatus()
    }
}

ClassMethod CheckNarrativeContract(payload As %DynamicObject, expectedPanel As %String, ByRef failures As %Integer) [ Internal ]
{
    If '$ISOBJECT(payload) {
        Do ..Fail("Payload is not an object", .failures)
        Quit
    }

    If payload.%Get("panel") '= expectedPanel {
        Do ..Fail("Panel mismatch: expected " _ expectedPanel _ ", got " _ payload.%Get("panel"), .failures)
    } Else {
        Do ..Pass("Panel matches expected: " _ expectedPanel)
    }

    Set requiredSections = [
        "Your Most Recent Results",
        "Your Trend",
        "What This Means",
        "Context From Your Medical Record",
        "Questions To Ask Your Doctor",
        "Suggested Next Step"
    ]

    Set sections = payload.%Get("sections")
    If '$ISOBJECT(sections) {
        Do ..Fail("sections object missing", .failures)
        Quit
    }

    For i=0:1:(requiredSections.%Size()-1) {
        Set sectionName = requiredSections.%Get(i)
        If 'sections.%IsDefined(sectionName) {
            Do ..Fail("Missing section: " _ sectionName, .failures)
            Continue
        }

        Set lines = sections.%Get(sectionName)
        If '$ISOBJECT(lines) || (lines.%Size()=0) {
            Do ..Fail("Empty section: " _ sectionName, .failures)
        } Else {
            Do ..Pass("Section present: " _ sectionName)
        }
    }

    Set mode = payload.%Get("retrievalMode")
    If (mode = "") {
        Do ..Fail("retrievalMode missing", .failures)
    } Else {
        Do ..Pass("retrievalMode present: " _ mode)
    }
}

ClassMethod Pass(msg As %String) [ Internal ]
{
    Write "[PASS] ", msg, !
}

ClassMethod Fail(msg As %String, ByRef failures As %Integer) [ Internal ]
{
    Set failures = failures + 1
    Write "[FAIL] ", msg, !
}

}
