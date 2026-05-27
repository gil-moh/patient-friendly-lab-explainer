Include %occStatus

Class Sample.AI.Tools.LabReadOnly Extends %RegisteredObject
{

/// Fetch one patient resource by logical id.
ClassMethod GetPatientById(patientId As %String) As %DynamicObject
{
    If patientId = "" {
        Return {"error":"patientId is required"}
    }
    Return ..GetFHIR("Patient/" _ ..UrlEncode(patientId))
}

/// Fetch Observation bundle for a patient and panel code set.
/// panel values: a1c, lipids, cbc, cmp.
ClassMethod GetObservationsByPanel(patientId As %String, panel As %String, limit As %Integer = 200) As %DynamicObject
{
    If patientId = "" {
        Return {"error":"patientId is required"}
    }

    Set normalizedPanel = ..NormalizePanel(panel)
    Set codeSet = ..GetPanelCodeSet(normalizedPanel)

    Set max = $SELECT(limit>500:500, limit<1:1, 1:limit)
    Set query = "patient=" _ ..UrlEncode(patientId) _ "&_count=" _ max _ "&_sort=-date"
    If codeSet '= "" {
        Set query = query _ "&code=" _ ..UrlEncode(codeSet)
    }

    Set bundle = ..GetFHIR("Observation?" _ query)
    If ..SafeGet(bundle, "error") '= "" {
        Return bundle
    }

    Return {
        "panel": (normalizedPanel),
        "patientId": (patientId),
        "codeSet": (codeSet),
        "bundle": (bundle)
    }
}

/// Fetch allergy/intolerance records for a patient.
ClassMethod GetAllergies(patientId As %String, limit As %Integer = 100) As %DynamicObject
{
    If patientId = "" {
        Return {"error":"patientId is required"}
    }

    Set max = $SELECT(limit>500:500, limit<1:1, 1:limit)
    Set query = "patient=" _ ..UrlEncode(patientId) _ "&_count=" _ max
    Return ..GetFHIR("AllergyIntolerance?" _ query)
}

/// Fetch family history records for a patient.
ClassMethod GetFamilyHistory(patientId As %String, limit As %Integer = 100) As %DynamicObject
{
    If patientId = "" {
        Return {"error":"patientId is required"}
    }

    Set max = $SELECT(limit>500:500, limit<1:1, 1:limit)
    Set query = "patient=" _ ..UrlEncode(patientId) _ "&_count=" _ max
    Return ..GetFHIR("FamilyMemberHistory?" _ query)
}

/// Fetch active/relevant conditions for context-aware lab interpretation.
ClassMethod GetConditions(patientId As %String, limit As %Integer = 100) As %DynamicObject
{
    If patientId = "" {
        Return {"error":"patientId is required"}
    }

    Set max = $SELECT(limit>500:500, limit<1:1, 1:limit)
    Set query = "patient=" _ ..UrlEncode(patientId) _ "&_count=" _ max
    Return ..GetFHIR("Condition?" _ query)
}

/// Fetch medication requests to provide treatment-context interpretation.
ClassMethod GetMedicationRequests(patientId As %String, limit As %Integer = 100) As %DynamicObject
{
    If patientId = "" {
        Return {"error":"patientId is required"}
    }

    Set max = $SELECT(limit>500:500, limit<1:1, 1:limit)
    Set query = "patient=" _ ..UrlEncode(patientId) _ "&_count=" _ max
    Return ..GetFHIR("MedicationRequest?" _ query)
}

/// Fetch diagnostic reports to provide broader diagnostic context.
ClassMethod GetDiagnosticReports(patientId As %String, limit As %Integer = 100) As %DynamicObject
{
    If patientId = "" {
        Return {"error":"patientId is required"}
    }

    Set max = $SELECT(limit>500:500, limit<1:1, 1:limit)
    Set query = "patient=" _ ..UrlEncode(patientId) _ "&_count=" _ max
    Return ..GetFHIR("DiagnosticReport?" _ query)
}

/// Fetch observations by an explicit LOINC code set.
ClassMethod GetObservationsByCodes(patientId As %String, codeSet As %String, limit As %Integer = 200) As %DynamicObject
{
    If patientId = "" {
        Return {"error":"patientId is required"}
    }

    Set max = $SELECT(limit>500:500, limit<1:1, 1:limit)
    Set query = "patient=" _ ..UrlEncode(patientId) _ "&_count=" _ max _ "&_sort=-date"
    If codeSet '= "" {
        Set query = query _ "&code=" _ ..UrlEncode(codeSet)
    }

    Return ..GetFHIR("Observation?" _ query)
}

/// Vital signs and body measurements used for context (BP, pulse, SpO2, temp, weight, height, BMI).
ClassMethod GetVitalAndBodyObservations(patientId As %String, limit As %Integer = 250) As %DynamicObject
{
    Set codeSet = "85354-9,8480-6,8462-4,8867-4,59408-5,8310-5,29463-7,8302-2,39156-5"
    Return ..GetObservationsByCodes(patientId, codeSet, limit)
}

/// Inflammation and nutrition markers for context-aware interpretation.
ClassMethod GetInflammationNutritionObservations(patientId As %String, limit As %Integer = 250) As %DynamicObject
{
    Set codeSet = "1988-5,4537-7,6690-2,2276-4,2132-9,2284-8,2498-4"
    Return ..GetObservationsByCodes(patientId, codeSet, limit)
}

/// Social and behavioral context observations (starter set).
ClassMethod GetSocialRiskObservations(patientId As %String, limit As %Integer = 150) As %DynamicObject
{
    Set codeSet = "72166-2,11366-2,74013-4"
    Return ..GetObservationsByCodes(patientId, codeSet, limit)
}

/// Fetch recent encounters.
ClassMethod GetEncounters(patientId As %String, limit As %Integer = 100) As %DynamicObject
{
    If patientId = "" {
        Return {"error":"patientId is required"}
    }

    Set max = $SELECT(limit>500:500, limit<1:1, 1:limit)
    Set query = "patient=" _ ..UrlEncode(patientId) _ "&_count=" _ max _ "&_sort=-date"
    Return ..GetFHIR("Encounter?" _ query)
}

/// Fetch procedures that may explain transient lab changes.
ClassMethod GetProcedures(patientId As %String, limit As %Integer = 100) As %DynamicObject
{
    If patientId = "" {
        Return {"error":"patientId is required"}
    }

    Set max = $SELECT(limit>500:500, limit<1:1, 1:limit)
    Set query = "patient=" _ ..UrlEncode(patientId) _ "&_count=" _ max _ "&_sort=-date"
    Return ..GetFHIR("Procedure?" _ query)
}

/// Fetch planned/active service requests (follow-up gaps context).
ClassMethod GetServiceRequests(patientId As %String, limit As %Integer = 100) As %DynamicObject
{
    If patientId = "" {
        Return {"error":"patientId is required"}
    }

    Set max = $SELECT(limit>500:500, limit<1:1, 1:limit)
    Set query = "patient=" _ ..UrlEncode(patientId) _ "&_count=" _ max
    Return ..GetFHIR("ServiceRequest?" _ query)
}

/// Fetch appointments for adherence/follow-up context.
ClassMethod GetAppointments(patientId As %String, limit As %Integer = 100) As %DynamicObject
{
    If patientId = "" {
        Return {"error":"patientId is required"}
    }

    Set max = $SELECT(limit>500:500, limit<1:1, 1:limit)
    Set query = "patient=" _ ..UrlEncode(patientId) _ "&_count=" _ max
    Return ..GetFHIR("Appointment?" _ query)
}

ClassMethod NormalizePanel(panel As %String) As %String [ Internal ]
{
    Set p = $ZCONVERT($ZSTRIP(panel, "<>W"), "L")
    If p = "" {
        Return "a1c"
    }
    If (p [ "a1c") || (p [ "hba1c") {
        Return "a1c"
    }
    If (p [ "lipid") || (p [ "cholesterol") {
        Return "lipids"
    }
    If p [ "cbc" {
        Return "cbc"
    }
    If (p [ "cmp") || (p [ "metabolic") {
        Return "cmp"
    }
    Return p
}

ClassMethod GetPanelCodeSet(panel As %String) As %String [ Internal ]
{
    // Comma-separated OR search values for FHIR Observation.code.
    If panel = "a1c" {
        Return "4548-4"
    }

    If panel = "lipids" {
        // Total cholesterol, HDL, LDL, triglycerides.
        Return "2093-3,2085-9,13457-7,2571-8"
    }

    If panel = "cbc" {
        // Hemoglobin, WBC, platelets, hematocrit.
        Return "718-7,6690-2,777-3,4544-3"
    }

    If panel = "cmp" {
        // Starter + common CMP analytes.
        Return "2339-0,2160-0,2823-3,2951-2,2885-2,2075-0,6768-6,1920-8,1975-2,1742-6,3094-0,17861-6,1989-3"
    }

    Return ""
}

ClassMethod GetFHIR(path As %String) As %DynamicObject [ Internal ]
{
    Set baseUrl = ..GetBaseUrl()
    Set fullUrl = baseUrl _ "/" _ path

    Set req = ##class(%Net.HttpRequest).%New()
    Set req.SSLCheckServerIdentity = 0

    Set basicUser = $SYSTEM.Util.GetEnviron("FHIR_BASIC_USER")
    If basicUser = "" {
        Set basicUser = $GET(^||ENV("FHIR_BASIC_USER"))
    }
    Set basicPass = $SYSTEM.Util.GetEnviron("FHIR_BASIC_PASS")
    If basicPass = "" {
        Set basicPass = $GET(^||ENV("FHIR_BASIC_PASS"))
    }

    If (basicUser '= "") && (basicPass '= "") {
        Set req.Username = basicUser
        Set req.Password = basicPass
    } Else {
        Set token = $SYSTEM.Util.GetEnviron("FHIR_BEARER_TOKEN")
        If token = "" {
            Set token = $GET(^||ENV("FHIR_BEARER_TOKEN"))
        }
        If token '= "" {
            Do req.SetHeader("Authorization", "Bearer " _ token)
        }
    }

    Do req.SetHeader("Accept", "application/fhir+json")

    Set sc = req.Get(fullUrl)
    If $$$ISERR(sc) {
        Return {
            "error":"HTTP request failed",
            "status":($SYSTEM.Status.GetErrorText(sc)),
            "url":(fullUrl)
        }
    }

    Set statusCode = +req.HttpResponse.StatusCode
    Set body = ..ReadResponseBody(req.HttpResponse.Data)

    If (statusCode < 200) || (statusCode > 299) {
        Return {
            "error":"FHIR request failed",
            "statusCode":(statusCode),
            "url":(fullUrl),
            "body":(body)
        }
    }

    Try {
        Return ##class(%DynamicAbstractObject).%FromJSON(body)
    } Catch ex {
        Return {
            "error":"FHIR parse failed",
            "url":(fullUrl),
            "body":(body)
        }
    }
}

ClassMethod GetBaseUrl() As %String [ Internal ]
{
    Set base = $SYSTEM.Util.GetEnviron("FHIR_BASE_URL")
    If base = "" {
        Set base = $GET(^||ENV("FHIR_BASE_URL"))
    }
    If base = "" {
        Set base = "http://localhost:52773/fhir/r4"
    }
    Return $ZSTRIP(base, "<W", "/")
}

ClassMethod ReadResponseBody(stream As %Stream.Object) As %String [ Internal ]
{
    If '$ISOBJECT(stream) {
        Return ""
    }
    Set out = ""
    While 'stream.AtEnd {
        Set out = out _ stream.Read(32000)
    }
    Return out
}

ClassMethod UrlEncode(value As %String) As %String [ Internal ]
{
    Return $ZCONVERT(value, "O", "URL")
}

ClassMethod SafeGet(obj As %DynamicAbstractObject, key As %String) As %String [ Internal ]
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
