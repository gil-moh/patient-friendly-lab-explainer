Include %occStatus

Class Sample.AI.Tools.LabTrendEngine Extends %RegisteredObject
{

/// Build deterministic trend payload for one patient panel.
ClassMethod BuildPanelTrend(patientId As %String, panel As %String, limit As %Integer = 200) As %DynamicObject
{
    Set normalizedPanel = ##class(Sample.AI.Tools.LabReadOnly).NormalizePanel(panel)
    Set obsResponse = ##class(Sample.AI.Tools.LabReadOnly).GetObservationsByPanel(patientId, normalizedPanel, limit)

    If ..GetSafeText(obsResponse, "error") '= "" {
        Return obsResponse
    }

    Set bundle = obsResponse.%Get("bundle")
    Return ..BuildPanelTrendFromBundle(patientId, normalizedPanel, bundle)
}

ClassMethod BuildPanelTrendFromBundle(patientId As %String, panel As %String, bundle As %DynamicObject) As %DynamicObject
{
    Set normalizedPanel = ##class(Sample.AI.Tools.LabReadOnly).NormalizePanel(panel)
    Set entries = ""
    If $ISOBJECT(bundle) {
        Set entries = bundle.%Get("entry")
    }

    Set analytes = ..GetPanelAnalyteDefinitions(normalizedPanel)

    Set trendItems = []
    If $ISOBJECT(analytes) {
        For i=0:1:(analytes.%Size()-1) {
            Set def = analytes.%Get(i)
            Set code = def.%Get("code")
            Set points = []

            If $ISOBJECT(entries) {
                For j=0:1:(entries.%Size()-1) {
                    Set item = entries.%Get(j)
                    If '$ISOBJECT(item) {
                        Continue
                    }
                    Set obs = item.%Get("resource")
                    If '$ISOBJECT(obs) {
                        Continue
                    }

                    Set loinc = ..GetObservationLoinc(obs)
                    If loinc '= code {
                        Continue
                    }

                    Set normalized = ..NormalizeObservation(obs)
                    If '$ISOBJECT(normalized) {
                        Continue
                    }
                    If normalized.%Get("hasNumeric") '= 1 {
                        Continue
                    }

                    Do points.%Push(normalized)
                }
            }

            Do ..SortPointsByDateDesc(.points)
            Set trend = ..BuildAnalyteTrend(def, points)
            Do trendItems.%Push(trend)
        }
    }

    Return {
        "patientId": (patientId),
        "panel": (normalizedPanel),
        "generatedAt": ($ZDATETIME($HOROLOG, 3, 1)),
        "itemCount": (trendItems.%Size()),
        "items": (trendItems)
    }
}

ClassMethod GetPanelAnalyteDefinitions(panel As %String) As %DynamicArray [ Internal ]
{
    Set defs = []

    If panel = "a1c" {
        Do defs.%Push(..Analyte("4548-4", "Hemoglobin A1c", "%", 0, 6.5, 7.0))
        Return defs
    }

    If panel = "lipids" {
        Do defs.%Push(..Analyte("2093-3", "Total cholesterol", "mg/dL", 120, 200, 200))
        Do defs.%Push(..Analyte("2085-9", "HDL cholesterol", "mg/dL", 40, 120, 40, 1))
        Do defs.%Push(..Analyte("13457-7", "LDL cholesterol", "mg/dL", 0, 100, 100))
        Do defs.%Push(..Analyte("2571-8", "Triglycerides", "mg/dL", 0, 150, 150))
        Return defs
    }

    If panel = "cbc" {
        Do defs.%Push(..Analyte("718-7", "Hemoglobin", "g/dL", 12.0, 17.5, 12.0))
        Do defs.%Push(..Analyte("6690-2", "White blood cell count", "10*3/uL", 4.0, 11.0, 4.0))
        Do defs.%Push(..Analyte("777-3", "Platelets", "10*3/uL", 150, 450, 150))
        Do defs.%Push(..Analyte("4544-3", "Hematocrit", "%", 36, 52, 36))
        Return defs
    }

    // CMP (starter + common)
    Do defs.%Push(..Analyte("2339-0", "Glucose", "mg/dL", 70, 99, 99))
    Do defs.%Push(..Analyte("2160-0", "Creatinine", "mg/dL", 0.6, 1.3, 1.3))
    Do defs.%Push(..Analyte("2823-3", "Potassium", "mmol/L", 3.5, 5.1, 5.1))
    Do defs.%Push(..Analyte("2951-2", "Sodium", "mmol/L", 135, 145, 145))
    Do defs.%Push(..Analyte("2885-2", "Protein total", "g/dL", 6.0, 8.3, 8.3))
    Do defs.%Push(..Analyte("2075-0", "Chloride", "mmol/L", 98, 107, 107))
    Do defs.%Push(..Analyte("6768-6", "Alkaline phosphatase", "U/L", 44, 147, 147))
    Do defs.%Push(..Analyte("1920-8", "AST", "U/L", 10, 40, 40))
    Do defs.%Push(..Analyte("1975-2", "Bilirubin total", "mg/dL", 0.1, 1.2, 1.2))
    Do defs.%Push(..Analyte("1742-6", "ALT", "U/L", 7, 56, 56))
    Do defs.%Push(..Analyte("3094-0", "BUN", "mg/dL", 7, 20, 20))
    Do defs.%Push(..Analyte("17861-6", "Calcium", "mg/dL", 8.6, 10.2, 9.2))
    Do defs.%Push(..Analyte("1989-3", "Vitamin D 25-hydroxy", "ng/mL", 20, 80, 30))

    Return defs
}

ClassMethod NormalizeObservation(obs As %DynamicObject) As %DynamicObject [ Internal ]
{
    Set out = {}
    Set out.id = ..GetSafeText(obs, "id")
    Set out.effective = ..GetObservationDate(obs)
    Set out.display = ..GetObservationDisplay(obs)
    Set out.unit = ""
    Set out.valueText = ""
    Set out.value = 0
    Set out.hasNumeric = 0

    Set q = obs.%Get("valueQuantity")
    If $ISOBJECT(q) {
        Set rawValue = ..GetSafeText(q, "value")
        Set out.unit = ..GetSafeText(q, "unit")
        Set out.valueText = $ZSTRIP(rawValue _ " " _ out.unit, "<>W")
        If ..IsNumericText(rawValue) {
            Set out.value = +rawValue
            Set out.hasNumeric = 1
            Return out
        }
    }

    Set valueString = ..GetSafeText(obs, "valueString")
    Set out.valueText = valueString
    If ..IsNumericText(valueString) {
        Set out.value = +valueString
        Set out.hasNumeric = 1
    }

    Return out
}

ClassMethod BuildAnalyteTrend(def As %DynamicObject, points As %DynamicArray) As %DynamicObject [ Internal ]
{
    Set out = {}
    Set out.code = def.%Get("code")
    Set out.label = def.%Get("label")
    Set out.unit = def.%Get("unit")
    Set out.pointCount = 0
    Set out.status = "no-data"
    Set out.trendDirection = "unknown"
    Set out.latest = ""
    Set out.previous = ""
    Set out.delta = ""

    If '$ISOBJECT(points) {
        Return out
    }

    Set count = points.%Size()
    Set out.pointCount = count
    If count = 0 {
        Return out
    }

    Set latest = points.%Get(0)
    Set out.latest = latest

    Set latestValue = +latest.%Get("value")
    Set out.status = ..ClassifyStatus(def, latestValue)

    If count > 1 {
        Set previous = points.%Get(1)
        Set out.previous = previous
        Set prevValue = +previous.%Get("value")
        Set delta = latestValue - prevValue
        Set out.delta = delta

        If delta > 0 {
            Set out.trendDirection = "up"
        } ElseIf delta < 0 {
            Set out.trendDirection = "down"
        } Else {
            Set out.trendDirection = "stable"
        }
    } Else {
        Set out.trendDirection = "single-point"
    }

    Set out.summary = ..BuildTrendSummary(out)
    Return out
}

ClassMethod BuildTrendSummary(item As %DynamicObject) As %String [ Internal ]
{
    Set label = item.%Get("label")
    Set status = item.%Get("status")
    Set trend = item.%Get("trendDirection")
    Set latest = item.%Get("latest")

    If '$ISOBJECT(latest) {
        Return label _ ": no data"
    }

    Set value = latest.%Get("value")
    Set unit = latest.%Get("unit")
    Set txt = label _ " is " _ value _ " " _ unit _ " (" _ status _ ")"

    If trend = "single-point" {
        Return txt _ "; no prior value for trend."
    }

    If trend = "up" {
        Return txt _ "; trending up from prior result."
    }
    If trend = "down" {
        Return txt _ "; trending down from prior result."
    }
    If trend = "stable" {
        Return txt _ "; stable versus prior result."
    }

    Return txt
}

ClassMethod ClassifyStatus(def As %DynamicObject, value As %Double) As %String [ Internal ]
{
    Set low = +def.%Get("low")
    Set high = +def.%Get("high")
    Set highIsBad = +def.%Get("highIsBad")

    If value < low {
        Return "low"
    }

    If value > high {
        If highIsBad=0 {
            Return "high-good"
        }
        Return "high"
    }

    Return "in-range"
}

ClassMethod Analyte(code As %String, label As %String, unit As %String, low As %Double, high As %Double, target As %Double, highIsBad As %Integer = 1) As %DynamicObject [ Internal ]
{
    Set o = {}
    Set o.code = code
    Set o.label = label
    Set o.unit = unit
    Set o.low = low
    Set o.high = high
    Set o.target = target
    Set o.highIsBad = highIsBad
    Return o
}

ClassMethod GetObservationLoinc(obs As %DynamicObject) As %String [ Internal ]
{
    If '$ISOBJECT(obs) {
        Return ""
    }
    Set codeObj = obs.%Get("code")
    If '$ISOBJECT(codeObj) {
        Return ""
    }
    Set coding = codeObj.%Get("coding")
    If '$ISOBJECT(coding) {
        Return ""
    }

    For i=0:1:(coding.%Size()-1) {
        Set c = coding.%Get(i)
        If '$ISOBJECT(c) {
            Continue
        }
        Set system = ..GetSafeText(c, "system")
        Set code = ..GetSafeText(c, "code")
        If (system [ "loinc") && (code '= "") {
            Return code
        }
    }
    Return ""
}

ClassMethod GetObservationDisplay(obs As %DynamicObject) As %String [ Internal ]
{
    Set codeObj = obs.%Get("code")
    If '$ISOBJECT(codeObj) {
        Return "Observation"
    }

    Set text = ..GetSafeText(codeObj, "text")
    If text '= "" {
        Return text
    }

    Set coding = codeObj.%Get("coding")
    If $ISOBJECT(coding) && (coding.%Size()>0) {
        Set c0 = coding.%Get(0)
        If $ISOBJECT(c0) {
            Set display = ..GetSafeText(c0, "display")
            If display '= "" {
                Return display
            }
        }
    }

    Return "Observation"
}

ClassMethod GetObservationDate(obs As %DynamicObject) As %String [ Internal ]
{
    Set dt = ..GetSafeText(obs, "effectiveDateTime")
    If dt '= "" {
        Return dt
    }
    Set dt = ..GetSafeText(obs, "issued")
    If dt '= "" {
        Return dt
    }

    Set p = obs.%Get("effectivePeriod")
    If $ISOBJECT(p) {
        Set dt = ..GetSafeText(p, "start")
        If dt '= "" {
            Return dt
        }
    }

    Return ""
}

ClassMethod SortPointsByDateDesc(ByRef points As %DynamicArray) [ Internal ]
{
    If '$ISOBJECT(points) {
        Quit
    }

    Set n = points.%Size()
    If n < 2 {
        Quit
    }

    For i=0:1:(n-2) {
        For j=(i+1):1:(n-1) {
            Set a = points.%Get(i)
            Set b = points.%Get(j)
            Set da = $ZSTRIP(a.%Get("effective"), "<>W")
            Set db = $ZSTRIP(b.%Get("effective"), "<>W")
            If db > da {
                Set tmp = a
                Do points.%Set(i, b)
                Do points.%Set(j, tmp)
            }
        }
    }
}

ClassMethod IsNumericText(raw As %String) As %Boolean [ Internal ]
{
    Set t = $ZSTRIP(raw, "<W")
    If t = "" {
        Return 0
    }

    If t?1(1"+",1"-").N {
        Return 1
    }
    If t?1(1"+",1"-").N1"."1.N {
        Return 1
    }
    If t?1.N {
        Return 1
    }
    If t?1.N1"."1.N {
        Return 1
    }

    Return 0
}

ClassMethod GetSafeText(obj, key As %String) As %String [ Internal ]
{
    If '$ISOBJECT(obj) {
        Return ""
    }

    Try {
        Set value = obj.%Get(key)
        Return value
    } Catch ex {
        Return ""
    }
}

}
