Include %occStatus

Class Sample.AI.Tools.PatientLabExplainer Extends %RegisteredObject
{

/// Builds deterministic patient-facing narrative payload from live FHIR trend data.
ClassMethod BuildPatientLabNarrative(patientId As %String, panel As %String) As %DynamicObject
{
    Set normalizedPanel = ##class(Sample.AI.Tools.LabReadOnly).NormalizePanel(panel)
    Set trend = ##class(Sample.AI.Tools.LabTrendEngine).BuildPanelTrend(patientId, normalizedPanel, 300)
    Set patient = ##class(Sample.AI.Tools.LabReadOnly).GetPatientById(patientId)
    Set allergies = ##class(Sample.AI.Tools.LabReadOnly).GetAllergies(patientId, 100)
    Set family = ##class(Sample.AI.Tools.LabReadOnly).GetFamilyHistory(patientId, 100)
    Set conditions = ##class(Sample.AI.Tools.LabReadOnly).GetConditions(patientId, 100)
    Set meds = ##class(Sample.AI.Tools.LabReadOnly).GetMedicationRequests(patientId, 100)
    Set reports = ##class(Sample.AI.Tools.LabReadOnly).GetDiagnosticReports(patientId, 100)
    Set vitalBody = ##class(Sample.AI.Tools.LabReadOnly).GetVitalAndBodyObservations(patientId, 250)
    Set inflamNutri = ##class(Sample.AI.Tools.LabReadOnly).GetInflammationNutritionObservations(patientId, 250)
    Set socialRisk = ##class(Sample.AI.Tools.LabReadOnly).GetSocialRiskObservations(patientId, 150)
    Set encounters = ##class(Sample.AI.Tools.LabReadOnly).GetEncounters(patientId, 100)
    Set procedures = ##class(Sample.AI.Tools.LabReadOnly).GetProcedures(patientId, 100)
    Set serviceRequests = ##class(Sample.AI.Tools.LabReadOnly).GetServiceRequests(patientId, 100)
    Set appointments = ##class(Sample.AI.Tools.LabReadOnly).GetAppointments(patientId, 100)

    Set context = {}
    Set context.patient = patient
    Set context.allergies = allergies
    Set context.familyHistory = family
    Set context.conditions = conditions
    Set context.medications = meds
    Set context.diagnosticReports = reports
    Set context.vitalBody = vitalBody
    Set context.inflammationNutrition = inflamNutri
    Set context.socialRisk = socialRisk
    Set context.encounters = encounters
    Set context.procedures = procedures
    Set context.serviceRequests = serviceRequests
    Set context.appointments = appointments

    If ..GetSafeText(trend, "error") '= "" {
        Return trend
    }

    Return ..BuildNarrativeFromTrend(patientId, normalizedPanel, trend, context)
}

ClassMethod BuildNarrativeFromTrend(patientId As %String, panel As %String, trend As %DynamicObject, context As %DynamicObject = "") As %DynamicObject
{
    Set sections = {}
    Set items = trend.%Get("items")

    Set latestLines = ..BuildRecentResults(items)
    Set trendLines = ..BuildTrendLines(items)
    Set meaningLines = ..BuildMeaningLines(panel, items, context)
    Set contextLines = ..BuildClinicalContextLines(panel, items, context)
    Set infectionRecentLines = ..BuildActiveInfectionResultLines(context, 60)
    Set infectionMeaningLines = ..BuildActiveInfectionMeaningLines(context, 60)
    Set inflammationMeaningLines = ..BuildInflammationMeaningLines(context)
    Do ..AppendLines(.latestLines, infectionRecentLines)
    Do ..AppendLines(.meaningLines, infectionMeaningLines)
    Do ..AppendLines(.meaningLines, inflammationMeaningLines)

    Set query = ..BuildGuidanceQuery(panel, items)
    Set guidance = ##class(Sample.AI.Tools.LabEducationRetriever).GetExplanationSnippets(panel, query, 2)
    Set helpfulLines = ..BuildHelpfulLines(guidance)

    Set questionLines = ..BuildQuestionLines(panel, items)
    Do ..AddContextAwareQuestions(.questionLines, items, context)
    Set lifestyleLines = ..BuildCarefulLifestyleOptions(items, context)
    Set nextStep = ..BuildNextStep(items, context)

    Do sections.%Set("Your Most Recent Results", latestLines)
    Do sections.%Set("Your Trend", trendLines)
    Do sections.%Set("What This Means", meaningLines)
    Do sections.%Set("Context From Your Medical Record", contextLines)
    Do sections.%Set("Careful Lifestyle Options", lifestyleLines)
    Do sections.%Set("Questions To Ask Your Doctor", questionLines)
    Set nextStepLines = []
    Do nextStepLines.%Push(nextStep)
    Do sections.%Set("Suggested Next Step", nextStepLines)

    Set out = {}
    Set out.patientId = patientId
    Set out.panel = panel
    Set out.panelLabel = ..GetPanelDisplayLabel(panel)
    Set out.generatedAt = $ZDATETIME($HOROLOG, 3, 1)
    Set out.retrievalMode = ..GetSafeText(guidance, "mode")
    Set out.retrievalStatus = ..GetSafeText(guidance, "status")
    Set out.sections = sections
    Return out
}

ClassMethod GetPanelDisplayLabel(panel As %String) As %String [ Internal ]
{
    If panel = "a1c" {
        Return "Hemoglobin A1c"
    }
    If panel = "lipids" {
        Return "Cholesterol and Lipid Panel"
    }
    If panel = "cbc" {
        Return "Complete Blood Count"
    }
    If panel = "cmp" {
        Return "Comprehensive Metabolic Panel"
    }
    Return panel
}

ClassMethod BuildClinicalContextLines(panel As %String, items As %DynamicArray, context As %DynamicObject = "") As %DynamicArray [ Internal ]
{
    Set out = []
    Set age = ..GetPatientAgeYears(context)
    Set sex = ..GetPatientGender(context)

    If age'="" {
        If age<18 {
            Do out.%Push("Age context: pediatric ranges can differ from adult ranges, so your clinician may use age-specific reference limits.")
        } ElseIf age>65 {
            Do out.%Push("Age context: for older adults, treatment thresholds and goals may be individualized based on overall health and medications.")
        }
    }

    If sex'="" {
        If (panel="cmp") && ..HasHighByCode(items, "2160-0") {
            Do out.%Push("Sex and body-composition context can affect creatinine; your clinician may compare this value to your personal baseline.")
        }
    }

    If ..IsPregnant(context) {
        Do out.%Push("Pregnancy context was detected in your record. Some lab reference ranges and treatment thresholds are pregnancy-specific.")
        If panel = "lipids" {
            Do out.%Push("Lipid values can rise during pregnancy. Your clinician should interpret these results using pregnancy-specific expectations.")
        }
        If panel = "cbc" {
            Do out.%Push("Mild decreases in hemoglobin can occur during pregnancy because of normal blood-volume changes. Your clinician may also check iron status.")
            If ..HasLowByCode(items, "718-7") {
                Do out.%Push("For your current CBC, low hemoglobin may be partly explained by pregnancy-related blood-volume changes, but your clinician should still confirm iron status.")
            }
        }
    }

    If ..HasConditionKeyword(context, "chronic kidney") || ..HasConditionKeyword(context, "ckd") {
        If ..HasHighByCode(items, "2160-0") {
            Do out.%Push("Kidney-condition context is present. A higher creatinine may reflect your baseline pattern, so trend over time is especially important.")
        } Else {
            Do out.%Push("Kidney-condition context is present. Your clinician may use individualized kidney targets rather than general population cutoffs.")
        }
    }

    If ..HasConditionKeyword(context, "diabetes") {
        If panel = "a1c" {
            Do out.%Push("Diabetes context is present. A1c goals are personalized (for example by age, comorbidities, and hypoglycemia risk), so your target may differ from generic thresholds.")
        }
    }

    If (panel = "a1c") && (..HasMedicationKeyword(context, "insulin") || ..HasMedicationKeyword(context, "metformin") || ..HasMedicationKeyword(context, "glp") || ..HasMedicationKeyword(context, "semaglutide")) {
        Do out.%Push("Diabetes-treatment context is present in medication records. Lab interpretation should consider treatment stage and recent medication changes.")
    }

    If (panel = "lipids") && (..HasMedicationKeyword(context, "statin") || ..HasMedicationKeyword(context, "atorvastatin") || ..HasMedicationKeyword(context, "rosuvastatin") || ..HasMedicationKeyword(context, "ezetimibe")) {
        Do out.%Push("Lipid-treatment context is present in medication records. Cholesterol results should be interpreted against your treatment goals and dose history.")
    }

    If ..HasSupplementKeyword(context) {
        Do out.%Push("Supplement context is present in medication records. Vitamins and food supplements can change some lab results or explain part of the pattern, so your clinician should interpret them together with the lab trend and timing of the dose.")
    }

    If ..HasDiagnosticReportKeyword(context, "chronic kidney") || ..HasDiagnosticReportKeyword(context, "ckd") {
        Do out.%Push("Diagnostic report context suggests kidney disease history. Kidney-related labs may follow individualized baseline expectations.")
    }

    Do ..AddExpandedContextLines(.out, panel, items, context)

    If out.%Size()=0 {
        Do out.%Push("No specific non-lab context was found that changes interpretation today. If your health status changed, ask your clinician to reinterpret these labs in that context.")
    }

    Return out
}

ClassMethod AddContextAwareMeaning(ByRef out As %DynamicArray, panel As %String, items As %DynamicArray, context As %DynamicObject = "") [ Internal ]
{
    If ..IsPregnant(context) {
        Do out.%Push("Because pregnancy context was found, some results may need pregnancy-specific interpretation.")
    }

    If ..HasConditionKeyword(context, "chronic kidney") || ..HasConditionKeyword(context, "ckd") {
        Do out.%Push("Because kidney-condition context was found, this report should be interpreted against your baseline trend, not a single value alone.")
    }

    If ..HasConditionKeyword(context, "liver disease") {
        Do out.%Push("Because liver-condition context was found, liver enzyme changes may require condition-specific follow-up planning.")
    }

    If ..HasMedicationKeyword(context, "steroid") {
        Do out.%Push("Because steroid medication context was found, some glucose and white-cell values can be affected by treatment.")
    }

    If ..HasSupplementKeyword(context) {
        Do out.%Push("Because supplement context was found, some lab changes may reflect vitamins or food supplements rather than the underlying disease alone. Timing, dose, and brand can matter.")
    }

    If ..HasDiagnosticReportKeyword(context, "fatty liver") {
        Do out.%Push("Because prior diagnostic reports mention liver findings, mild liver-enzyme changes may need trend-based follow-up rather than isolated interpretation.")
    }
}

ClassMethod BuildCarefulLifestyleOptions(items As %DynamicArray, context As %DynamicObject = "") As %DynamicArray [ Internal ]
{
    Set out = []

    Set hasLowVitD = ..HasLowByCode(items, "1989-3")
    Set hasLowCalcium = ..HasLowByCode(items, "17861-6")
    Set familySkinCancer = ..HasFamilyHistorySkinCancer(context)
    Set dairyAllergy = ..HasAllergyKeyword(context, "dairy") || ..HasAllergyKeyword(context, "milk")
    Set fishAllergy = ..HasAllergyKeyword(context, "fish")

    If hasLowVitD {
        If familySkinCancer {
            Do out.%Push("Vitamin D is low. Because your family history may increase skin cancer risk, ask about vitamin D supplements instead of prolonged unprotected sun exposure. [source: Endocrine Society Vitamin D Guideline]")
            Do out.%Push("If using daylight exposure, keep it brief and use skin-protection-safe habits discussed with your clinician. [source: AAD Sun Safety Guidance]")
        } Else {
            Do out.%Push("Vitamin D is low. Discuss a measured supplement plan and safe daylight habits with your clinician rather than intensive sun exposure. [source: Endocrine Society Vitamin D Guideline]")
        }
    }

    If hasLowCalcium {
        If dairyAllergy {
            If fishAllergy {
                Do out.%Push("Calcium is low and you have dairy and fish allergy context. Ask about calcium + vitamin D supplements and non-dairy fortified foods (for example fortified soy beverages, tofu set with calcium, leafy greens). [source: NIH ODS Calcium Fact Sheet]")
            } Else {
                Do out.%Push("Calcium is low and dairy allergy is present. Consider non-dairy fortified foods and fish with soft edible bones such as sardines, plus supplement options if needed. Confirm with your clinician. [source: NIH ODS Calcium Fact Sheet]")
            }
        } Else {
            Do out.%Push("Calcium is low. Discuss calcium-rich food options and whether supplements are appropriate for you. [source: NIH ODS Calcium Fact Sheet]")
        }
    }

    Set findings = ..CollectActiveInfectionFindings(context, 60)
    Set hasResp = 0, hasSexual = 0, hasBlood = 0, hasFecal = 0, hasGeneralInfection = 0
    If $ISOBJECT(findings) {
        For i=0:1:(findings.%Size()-1) {
            Set f = findings.%Get(i)
            If '$ISOBJECT(f) {
                Continue
            }
            Set name = ..GetSafeText(f, "name")
            Set route = ..GetInfectionTransmissionRoute(name)
            If route = "respiratory" Set hasResp = 1
            If route = "sexual" Set hasSexual = 1
            If route = "blood-sexual" Set hasBlood = 1
            If route = "fecal-oral" Set hasFecal = 1
            If route = "general" Set hasGeneralInfection = 1
        }
    }

    If hasResp {
        Do out.%Push("Infection-spread precaution: because a recent respiratory infection test is positive, reduce close-contact exposure while symptomatic, improve ventilation, use masking in shared indoor spaces, and follow clinician/public-health isolation guidance.")
    }
    If hasSexual {
        Do out.%Push("Infection-spread precaution: because a recent sexually transmitted infection test is positive, avoid unprotected sexual contact until your clinician confirms treatment response and advises it is safer; discuss partner testing/treatment.")
    }
    If hasBlood {
        Do out.%Push("Infection-spread precaution: because a blood/sexual transmission risk infection is present, use barrier protection, avoid sharing needles or blood-contact items, and follow clinician guidance for partner protection.")
    }
    If hasFecal {
        Do out.%Push("Infection-spread precaution: because a recent gastrointestinal viral infection test is positive, use strict hand hygiene, careful food handling, and frequent high-touch surface cleaning to reduce household spread.")
    }
    If ('hasResp)&&('hasSexual)&&('hasBlood)&&('hasFecal)&&hasGeneralInfection {
        Do out.%Push("Infection-spread precaution: a recent infection test is positive. Follow clinician guidance to reduce transmission risk until follow-up confirms recovery.")
    }

    If ..HasWorseningTrend(items) {
        Do out.%Push("Treatment-adherence option: worsening trends can happen when doses are missed or timing is inconsistent. Take medications exactly as prescribed, and ask your care team to simplify the regimen if adherence is difficult.")
    }

    If ..HasHighOrRisingGlycemicSignal(items) {
        Do out.%Push("Metabolic-support option: glucose control appears to be worsening. Prioritize medication adherence, reduce refined sugars/late-night carbohydrates, and add regular low-risk exercise (for example walking) most days if medically safe.")
    }

    If ..HasHighOrRisingLipidSignal(items) {
        Do out.%Push("Cardiometabolic option: cholesterol-related values are elevated or rising. Reinforce medication adherence, increase fiber-rich foods, reduce saturated/trans fats, and maintain regular physical activity if medically safe.")
    }

    If ..HasLowByCode(items, "718-7") || ..HasLowByCode(items, "4544-3") {
        Do out.%Push("Energy-support option: anemia-pattern signals are present. Prioritize recovery, hydration, and discuss iron/B12/folate evaluation before starting supplements on your own.")
    }

    If out.%Size()=0 {
        Do out.%Push("No personalized lifestyle adjustment is suggested from current data. Keep routine healthy habits and review your plan at follow-up.")
    }

    Do out.%Push("Safety note: These options are educational and should be personalized with your clinician, especially if you have chronic conditions, pregnancy, or medication interactions.")

    Return out
}

ClassMethod GetInfectionTransmissionRoute(name As %String) As %String [ Internal ]
{
    Set n = $ZCONVERT(name, "L")

    If (n [ "covid") || (n [ "sars") || (n [ "influenza") || (n [ "rsv") || (n [ "adenovirus") {
        Return "respiratory"
    }
    If (n [ "norovirus") || (n [ "rotavirus") {
        Return "fecal-oral"
    }
    If (n [ "syphilis") || (n [ "gonorrhea") || (n [ "chlamydia") || (n [ "trichomon") || (n [ "hpv") || (n [ "herpes") {
        Return "sexual"
    }
    If (n [ "hiv") || (n [ "hepatitis b") || (n [ "hepatitis c") {
        Return "blood-sexual"
    }

    Return "general"
}

ClassMethod HasWorseningTrend(items As %DynamicArray) As %Boolean [ Internal ]
{
    If '$ISOBJECT(items) {
        Return 0
    }

    For i=0:1:(items.%Size()-1) {
        Set it = items.%Get(i)
        If '$ISOBJECT(it) {
            Continue
        }
        Set status = ..GetSafeText(it, "status")
        Set dir = ..GetSafeText(it, "trendDirection")
        If (status="high")&&(dir="up") Return 1
        If (status="low")&&(dir="down") Return 1
    }

    Return 0
}

ClassMethod HasHighOrRisingGlycemicSignal(items As %DynamicArray) As %Boolean [ Internal ]
{
    If ..HasWorseningByCode(items, "4548-4") Return 1
    If ..HasWorseningByCode(items, "2339-0") Return 1
    If ..HasHighByCode(items, "4548-4") Return 1
    If ..HasHighByCode(items, "2339-0") Return 1
    Return 0
}

ClassMethod HasHighOrRisingLipidSignal(items As %DynamicArray) As %Boolean [ Internal ]
{
    If ..HasWorseningByCode(items, "2093-3") Return 1
    If ..HasWorseningByCode(items, "13457-7") Return 1
    If ..HasWorseningByCode(items, "2571-8") Return 1
    If ..HasHighByCode(items, "2093-3") Return 1
    If ..HasHighByCode(items, "13457-7") Return 1
    If ..HasHighByCode(items, "2571-8") Return 1
    Return 0
}

ClassMethod HasWorseningByCode(items As %DynamicArray, code As %String) As %Boolean [ Internal ]
{
    If '$ISOBJECT(items) {
        Return 0
    }

    For i=0:1:(items.%Size()-1) {
        Set it = items.%Get(i)
        If '$ISOBJECT(it) {
            Continue
        }
        If ..GetSafeText(it, "code") '= code {
            Continue
        }

        Set status = ..GetSafeText(it, "status")
        Set dir = ..GetSafeText(it, "trendDirection")
        If (status="high")&&(dir="up") Return 1
        If (status="low")&&(dir="down") Return 1
    }

    Return 0
}

ClassMethod HasSupplementKeyword(context As %DynamicObject) As %Boolean [ Internal ]
{
    If '$ISOBJECT(context) {
        Return 0
    }

    Set keywords = "iron|ferrous|vitamin d|vitamin b12|b12|folate|folic acid|calcium|magnesium|multivitamin|prenatal|biotin|omega-3|fish oil|probiotic"
    If ..HasMedicationKeywordsAny(context, keywords) {
        Return 1
    }

    Return 0
}

ClassMethod HasMedicationKeywordsAny(context As %DynamicObject, keywords As %String) As %Boolean [ Internal ]
{
    If '$ISOBJECT(context) {
        Return 0
    }

    Set parts = $LENGTH(keywords, "|")
    For i=1:1:parts {
        Set kw = $PIECE(keywords, "|", i)
        If kw '= "" , ..HasMedicationKeyword(context, kw) {
            Return 1
        }
    }

    Return 0
}

ClassMethod AddContextAwareQuestions(ByRef out As %DynamicArray, items As %DynamicArray, context As %DynamicObject = "") [ Internal ]
{
    If ..HasLowByCode(items, "1989-3") && ..HasFamilyHistorySkinCancer(context) {
        Do out.%Push("Given my family history of skin cancer, what is the safest way to correct low vitamin D?")
    }

    If ..HasLowByCode(items, "17861-6") && ..HasAllergyKeyword(context, "dairy") {
        Do out.%Push("Because of my dairy allergy, which calcium sources or supplements are safest for me?")
    }

    If ..HasMedicationKeyword(context, "statin") || ..HasMedicationKeyword(context, "atorvastatin") || ..HasMedicationKeyword(context, "rosuvastatin") {
        Do out.%Push("How do these results compare with my expected response to current cholesterol medication?")
    }

    If ..HasDiagnosticReportKeyword(context, "ckd") || ..HasConditionKeyword(context, "chronic kidney") {
        Do out.%Push("Which values in this panel represent my baseline for kidney disease, and which values are new changes?")
    }

    If ..HasRecentMedicationChange(context, 120) {
        Do out.%Push("Could a recent medication change affect these lab results?")
    }

    If ..TryGetBMI(context, .bmi, .bmiSource) {
        Do out.%Push("How should my BMI and weight trend affect this plan?")
    }

    If ..ContextBundleContains(context, "appointments", "noshow") || ..ContextBundleContains(context, "appointments", "cancelled") {
        Do out.%Push("Can we set a clear follow-up schedule so important repeat labs are not missed?")
    }
}

ClassMethod AddExpandedContextLines(ByRef out As %DynamicArray, panel As %String, items As %DynamicArray, context As %DynamicObject = "") [ Internal ]
{
    Set bmi = ""
    Set bmiSource = ""
    If ..TryGetBMI(context, .bmi, .bmiSource) {
        Set bmiText = +$JUSTIFY(bmi,0,1)
        Set bmiClass = ..ClassifyBMI(bmi)
        Set msg = "Body composition context: BMI is " _ bmiText _ " (" _ bmiClass _ ")"
        If bmiSource '= "" {
            Set msg = msg _ " from " _ bmiSource
        }
        Set msg = msg _ "."
        Do out.%Push(msg)
        If ..IsPregnant(context) {
            Do out.%Push("Pregnancy note: BMI and weight goals are interpreted differently in pregnancy, so use pregnancy-specific guidance.")
        }
    }

    If ..HasRecentMedicationChange(context, 120) {
        Do out.%Push("Medication timing context: a recent medication start or update was detected, which can temporarily shift lab values.")
    }

    If ..HasConditionKeyword(context, "chronic kidney disease stage") || ..HasDiagnosticReportKeyword(context, "fibrosis") || ..HasDiagnosticReportKeyword(context, "cirrhosis") {
        Do out.%Push("Staging context: chronic disease stage information appears in your record, so lab targets may be individualized by stage.")
    }

    If ..IsPregnant(context) {
        If ..HasConditionKeyword(context, "first trimester") {
            Do out.%Push("Pregnancy timeline context: first-trimester status is recorded; interpretation should follow trimester-specific expectations.")
        } ElseIf ..HasConditionKeyword(context, "second trimester") {
            Do out.%Push("Pregnancy timeline context: second-trimester status is recorded; interpretation should follow trimester-specific expectations.")
        } ElseIf ..HasConditionKeyword(context, "third trimester") {
            Do out.%Push("Pregnancy timeline context: third-trimester status is recorded; interpretation should follow trimester-specific expectations.")
        }
    }

    Set burden = ..CountComorbiditySignals(context)
    If burden>=2 {
        Do out.%Push("Comorbidity context: multiple chronic conditions are documented, so care goals may prioritize overall risk balance over single-value normalization.")
    }

    Set sbp="", dbp="", unit=""
    If ..TryGetLatestObsValueByLoinc(context, "vitalBody", "8480-6", .sbp, .unit) && ..TryGetLatestObsValueByLoinc(context, "vitalBody", "8462-4", .dbp, .unit2) {
        If (+sbp>=140) || (+dbp>=90) {
            Do out.%Push("Vital-sign context: recent blood pressure appears elevated, which may influence kidney and cardiovascular risk interpretation.")
        }
    }

    Set spo2="", su=""
    If ..TryGetLatestObsValueByLoinc(context, "vitalBody", "59408-5", .spo2, .su) {
        If +spo2<92 {
            Do out.%Push("Vital-sign context: lower oxygen saturation was recorded recently; discuss whether this should modify current interpretation priorities.")
        }
    }

    If ..TryGetLatestObsValueByLoinc(context, "inflammationNutrition", "1988-5", .crp, .cu) || ..TryGetLatestObsValueByLoinc(context, "inflammationNutrition", "4537-7", .esr, .eu) {
        Do out.%Push("Inflammation context: inflammatory markers are available and can help distinguish transient inflammation from chronic disease patterns.")
    }

    Set hasStiSignal = 0
    If ..HasConditionKeyword(context, "hiv") || ..HasConditionKeyword(context, "syphilis") || ..HasConditionKeyword(context, "gonorrhea") || ..HasConditionKeyword(context, "chlamydia") || ..HasConditionKeyword(context, "trichomon") || ..HasConditionKeyword(context, "genital herpes") {
        Set hasStiSignal = 1
    }
    If ..HasDiagnosticReportKeyword(context, "hiv") || ..HasDiagnosticReportKeyword(context, "syphilis") || ..HasDiagnosticReportKeyword(context, "gonorrhea") || ..HasDiagnosticReportKeyword(context, "chlamydia") || ..HasDiagnosticReportKeyword(context, "trichomon") || ..HasDiagnosticReportKeyword(context, "herpes") {
        Set hasStiSignal = 1
    }
    If hasStiSignal {
        Do out.%Push("Infectious-disease context: your record includes positive STI/STD findings (for example HIV, syphilis, or gonorrhea), so these blood-count changes should be interpreted together with active infection treatment and close follow-up.")
    }

    If ..TryGetLatestObsValueByLoinc(context, "inflammationNutrition", "2276-4", .ferr, .fu) || ..TryGetLatestObsValueByLoinc(context, "inflammationNutrition", "2132-9", .b12, .bu) || ..TryGetLatestObsValueByLoinc(context, "inflammationNutrition", "2284-8", .fol, .fo) || ..TryGetLatestObsValueByLoinc(context, "inflammationNutrition", "2498-4", .iron, .iu) {
        Do out.%Push("Nutrition context: iron/vitamin markers are present and may explain selected abnormalities (for example anemia-related changes).")
    }

    If ..BundleEntryCount(context, "procedures")>0 || ..ContextBundleContains(context, "encounters", "inpatient") || ..ContextBundleContains(context, "encounters", "emergency") {
        Do out.%Push("Recent care context: procedures or acute-care encounters are documented and can cause temporary lab shifts.")
    }

    If ..HasLongitudinalHistory(items, 3) {
        Do out.%Push("Personal baseline context: multiple prior values are available, allowing interpretation against your own trend baseline rather than one isolated result.")
    }

    If ..BundleEntryCount(context, "socialRisk")>0 || ..ContextBundleContains(context, "socialRisk", "smok") || ..ContextBundleContains(context, "socialRisk", "alcohol") {
        Do out.%Push("Lifestyle risk context: behavioral or social risk data is present and may be relevant when setting realistic lab-improvement targets.")
    }

    If ..ContextBundleContains(context, "appointments", "noshow") || ..ContextBundleContains(context, "appointments", "cancelled") || ..ContextBundleContains(context, "serviceRequests", "active") {
        Do out.%Push("Follow-up context: pending requests or missed/canceled appointments were found, so completing follow-up may be important for safe trend interpretation.")
    }
}

ClassMethod HasLongitudinalHistory(items As %DynamicArray, minPoints As %Integer = 3) As %Boolean [ Internal ]
{
    If '$ISOBJECT(items) {
        Return 0
    }
    For i=0:1:(items.%Size()-1) {
        Set it = items.%Get(i)
        If '$ISOBJECT(it) {
            Continue
        }
        If +it.%Get("pointCount")>=minPoints {
            Return 1
        }
    }
    Return 0
}

ClassMethod TryGetBMI(context As %DynamicObject, ByRef bmi As %Double, ByRef source As %String) As %Boolean [ Internal ]
{
    Set bmi = ""
    Set source = ""

    If ..TryGetLatestObsValueByLoinc(context, "vitalBody", "39156-5", .bmiVal, .u) {
        Set bmi = +bmiVal
        Set source = "recorded BMI"
        Return 1
    }

    Set wt = ""
    Set ht = ""
    If '..TryGetLatestObsValueByLoinc(context, "vitalBody", "29463-7", .wt, .wu) {
        Return 0
    }
    If '..TryGetLatestObsValueByLoinc(context, "vitalBody", "8302-2", .ht, .hu) {
        Return 0
    }

    Set weightKg = +wt
    Set heightM = +ht
    If $ZCONVERT(hu, "L") [ "cm" {
        Set heightM = heightM/100
    }
    If heightM<=0 {
        Return 0
    }

    Set bmi = weightKg/(heightM*heightM)
    Set source = "height and weight"
    Return 1
}

ClassMethod ClassifyBMI(bmi As %Double) As %String [ Internal ]
{
    If bmi<18.5 Return "below usual range"
    If bmi<25 Return "usual range"
    If bmi<30 Return "above usual range"
    Return "high range"
}

ClassMethod TryGetLatestObsValueByLoinc(context As %DynamicObject, bundleKey As %String, loinc As %String, ByRef value As %Double, ByRef unit As %String) As %Boolean [ Internal ]
{
    Set value = ""
    Set unit = ""

    If '$ISOBJECT(context) {
        Return 0
    }
    Set bundle = context.%Get(bundleKey)
    If '$ISOBJECT(bundle) {
        Return 0
    }

    Set entries = bundle.%Get("entry")
    If '$ISOBJECT(entries) {
        Return 0
    }

    For i=0:1:(entries.%Size()-1) {
        Set e = entries.%Get(i)
        If '$ISOBJECT(e) {
            Continue
        }
        Set obs = e.%Get("resource")
        If '$ISOBJECT(obs) {
            Continue
        }
        If ..ObservationHasLoinc(obs, loinc)=0 {
            Continue
        }
        If ..TryGetObservationValue(obs, .value, .unit) {
            Return 1
        }
    }

    Return 0
}

ClassMethod ObservationHasLoinc(obs As %DynamicObject, loinc As %String) As %Boolean [ Internal ]
{
    If '$ISOBJECT(obs) {
        Return 0
    }
    Set codeObj = obs.%Get("code")
    If '$ISOBJECT(codeObj) {
        Return 0
    }
    Set coding = codeObj.%Get("coding")
    If '$ISOBJECT(coding) {
        Return 0
    }
    For i=0:1:(coding.%Size()-1) {
        Set c = coding.%Get(i)
        If '$ISOBJECT(c) {
            Continue
        }
        If ..GetSafeText(c, "code")=loinc {
            Return 1
        }
    }
    Return 0
}

ClassMethod TryGetObservationValue(obs As %DynamicObject, ByRef value As %Double, ByRef unit As %String) As %Boolean [ Internal ]
{
    Set value = ""
    Set unit = ""
    If '$ISOBJECT(obs) {
        Return 0
    }

    Set q = obs.%Get("valueQuantity")
    If $ISOBJECT(q) {
        Set value = +q.%Get("value")
        Set unit = ..GetSafeText(q, "unit")
        Return 1
    }

    Return 0
}

ClassMethod BundleEntryCount(context As %DynamicObject, key As %String) As %Integer [ Internal ]
{
    If '$ISOBJECT(context) {
        Return 0
    }
    Set bundle = context.%Get(key)
    If '$ISOBJECT(bundle) {
        Return 0
    }
    Set entries = bundle.%Get("entry")
    If '$ISOBJECT(entries) {
        Return 0
    }
    Return entries.%Size()
}

ClassMethod ContextBundleContains(context As %DynamicObject, key As %String, keyword As %String) As %Boolean [ Internal ]
{
    If '$ISOBJECT(context) {
        Return 0
    }
    Set bundle = context.%Get(key)
    If '$ISOBJECT(bundle) {
        Return 0
    }
    Try {
        Set json = $ZCONVERT(bundle.%ToJSON(), "L")
    } Catch ex {
        Return 0
    }
    Return json[$ZCONVERT(keyword, "L")
}

ClassMethod HasRecentMedicationChange(context As %DynamicObject, withinDays As %Integer = 120) As %Boolean [ Internal ]
{
    If '$ISOBJECT(context) {
        Return 0
    }

    Set bundle = context.%Get("medications")
    If '$ISOBJECT(bundle) {
        Return 0
    }
    Set entries = bundle.%Get("entry")
    If '$ISOBJECT(entries) {
        Return 0
    }

    Set today = +$PIECE($HOROLOG, ",", 1)
    For i=0:1:(entries.%Size()-1) {
        Set item = entries.%Get(i)
        If '$ISOBJECT(item) {
            Continue
        }
        Set resource = item.%Get("resource")
        If '$ISOBJECT(resource) {
            Continue
        }
        Set authored = ..GetSafeText(resource, "authoredOn")
        If authored = "" {
            Continue
        }
        Set h = ..FHIRDateToH(authored)
        If h="" {
            Continue
        }
        Set diff = today-h
        If (diff>=0) && (diff<=withinDays) {
            Return 1
        }
    }

    Return 0
}

ClassMethod FHIRDateToH(dateValue As %String) As %String [ Internal ]
{
    Set d = $EXTRACT(dateValue, 1, 10)
    If d="" {
        Return ""
    }
    Try {
        Return $ZDATEH(d, 3)
    } Catch ex {
        Return ""
    }
}

ClassMethod CountComorbiditySignals(context As %DynamicObject) As %Integer [ Internal ]
{
    Set count = 0
    If ..HasConditionKeyword(context, "diabetes") Set count=count+1
    If ..HasConditionKeyword(context, "chronic kidney") || ..HasConditionKeyword(context, "ckd") Set count=count+1
    If ..HasConditionKeyword(context, "heart failure") Set count=count+1
    If ..HasConditionKeyword(context, "copd") Set count=count+1
    If ..HasConditionKeyword(context, "cancer") Set count=count+1
    If ..HasConditionKeyword(context, "thyroid") Set count=count+1
    If ..HasConditionKeyword(context, "liver") Set count=count+1
    Return count
}

ClassMethod HasLowByCode(items As %DynamicArray, code As %String) As %Boolean [ Internal ]
{
    If '$ISOBJECT(items) {
        Return 0
    }

    For i=0:1:(items.%Size()-1) {
        Set it = items.%Get(i)
        If '$ISOBJECT(it) {
            Continue
        }
        If ..GetSafeText(it, "code") '= code {
            Continue
        }
        If ..GetSafeText(it, "status") = "low" {
            Return 1
        }
    }

    Return 0
}

ClassMethod HasHighByCode(items As %DynamicArray, code As %String) As %Boolean [ Internal ]
{
    If '$ISOBJECT(items) {
        Return 0
    }

    For i=0:1:(items.%Size()-1) {
        Set it = items.%Get(i)
        If '$ISOBJECT(it) {
            Continue
        }
        If ..GetSafeText(it, "code") '= code {
            Continue
        }
        If ..GetSafeText(it, "status") = "high" {
            Return 1
        }
    }

    Return 0
}

ClassMethod IsPregnant(context As %DynamicObject) As %Boolean [ Internal ]
{
    If ..HasConditionKeyword(context, "pregnan") {
        Return 1
    }
    If ..HasConditionKeyword(context, "gestation") {
        Return 1
    }
    Return 0
}

ClassMethod GetPatientGender(context As %DynamicObject) As %String [ Internal ]
{
    If '$ISOBJECT(context) {
        Return ""
    }
    Set patient = context.%Get("patient")
    If '$ISOBJECT(patient) {
        Return ""
    }
    Return $ZCONVERT(..GetSafeText(patient, "gender"), "L")
}

ClassMethod GetPatientAgeYears(context As %DynamicObject) As %String [ Internal ]
{
    If '$ISOBJECT(context) {
        Return ""
    }

    Set patient = context.%Get("patient")
    If '$ISOBJECT(patient) {
        Return ""
    }

    Set birthDate = ..GetSafeText(patient, "birthDate")
    If birthDate = "" {
        Return ""
    }

    Try {
        Set dobH = $ZDATEH(birthDate, 3)
        Set age = ($PIECE($HOROLOG, ",", 1) - dobH) \ 365
        If age<0 {
            Return ""
        }
        Return age
    } Catch ex {
        Return ""
    }
}

ClassMethod HasConditionKeyword(context As %DynamicObject, keyword As %String) As %Boolean [ Internal ]
{
    If '$ISOBJECT(context) {
        Return 0
    }

    Set bundle = context.%Get("conditions")
    If '$ISOBJECT(bundle) {
        Return 0
    }

    Set entries = bundle.%Get("entry")
    If '$ISOBJECT(entries) {
        Return 0
    }

    Set needle = $ZCONVERT(keyword, "L")
    For i=0:1:(entries.%Size()-1) {
        Set item = entries.%Get(i)
        If '$ISOBJECT(item) {
            Continue
        }
        Set resource = item.%Get("resource")
        If '$ISOBJECT(resource) {
            Continue
        }

        Set codeObj = resource.%Get("code")
        Set text = $ZCONVERT(..GetSafeText(codeObj, "text"), "L")
        If text [ needle {
            Return 1
        }

        Set coding = ""
        If $ISOBJECT(codeObj) {
            Set coding = codeObj.%Get("coding")
        }
        If $ISOBJECT(coding) {
            For j=0:1:(coding.%Size()-1) {
                Set c = coding.%Get(j)
                If '$ISOBJECT(c) {
                    Continue
                }
                Set display = $ZCONVERT(..GetSafeText(c, "display"), "L")
                Set code = $ZCONVERT(..GetSafeText(c, "code"), "L")
                If (display [ needle) || (code [ needle) {
                    Return 1
                }
            }
        }
    }

    Return 0
}

ClassMethod HasMedicationKeyword(context As %DynamicObject, keyword As %String) As %Boolean [ Internal ]
{
    If '$ISOBJECT(context) {
        Return 0
    }

    Set bundle = context.%Get("medications")
    If '$ISOBJECT(bundle) {
        Return 0
    }

    Set entries = bundle.%Get("entry")
    If '$ISOBJECT(entries) {
        Return 0
    }

    Set needle = $ZCONVERT(keyword, "L")
    For i=0:1:(entries.%Size()-1) {
        Set item = entries.%Get(i)
        If '$ISOBJECT(item) {
            Continue
        }

        Set resource = item.%Get("resource")
        If '$ISOBJECT(resource) {
            Continue
        }

        Set medCode = resource.%Get("medicationCodeableConcept")
        If $ISOBJECT(medCode) {
            Set text = $ZCONVERT(..GetSafeText(medCode, "text"), "L")
            If text [ needle {
                Return 1
            }

            Set coding = medCode.%Get("coding")
            If $ISOBJECT(coding) {
                For j=0:1:(coding.%Size()-1) {
                    Set c = coding.%Get(j)
                    If '$ISOBJECT(c) {
                        Continue
                    }
                    Set display = $ZCONVERT(..GetSafeText(c, "display"), "L")
                    Set code = $ZCONVERT(..GetSafeText(c, "code"), "L")
                    If (display [ needle) || (code [ needle) {
                        Return 1
                    }
                }
            }
        }

        Set medRef = $ZCONVERT(..GetSafeText(resource, "medicationReference"), "L")
        If medRef [ needle {
            Return 1
        }
    }

    Return 0
}

ClassMethod HasDiagnosticReportKeyword(context As %DynamicObject, keyword As %String) As %Boolean [ Internal ]
{
    If '$ISOBJECT(context) {
        Return 0
    }

    Set bundle = context.%Get("diagnosticReports")
    If '$ISOBJECT(bundle) {
        Return 0
    }

    Set entries = bundle.%Get("entry")
    If '$ISOBJECT(entries) {
        Return 0
    }

    Set needle = $ZCONVERT(keyword, "L")
    For i=0:1:(entries.%Size()-1) {
        Set item = entries.%Get(i)
        If '$ISOBJECT(item) {
            Continue
        }

        Set resource = item.%Get("resource")
        If '$ISOBJECT(resource) {
            Continue
        }

        Set conclusion = $ZCONVERT(..GetSafeText(resource, "conclusion"), "L")
        If conclusion [ needle {
            Return 1
        }

        Set codeObj = resource.%Get("code")
        If $ISOBJECT(codeObj) {
            Set text = $ZCONVERT(..GetSafeText(codeObj, "text"), "L")
            If text [ needle {
                Return 1
            }

            Set coding = codeObj.%Get("coding")
            If $ISOBJECT(coding) {
                For j=0:1:(coding.%Size()-1) {
                    Set c = coding.%Get(j)
                    If '$ISOBJECT(c) {
                        Continue
                    }
                    Set display = $ZCONVERT(..GetSafeText(c, "display"), "L")
                    Set code = $ZCONVERT(..GetSafeText(c, "code"), "L")
                    If (display [ needle) || (code [ needle) {
                        Return 1
                    }
                }
            }
        }
    }

    Return 0
}

ClassMethod HasAllergyKeyword(context As %DynamicObject, keyword As %String) As %Boolean [ Internal ]
{
    If '$ISOBJECT(context) {
        Return 0
    }

    Set bundle = context.%Get("allergies")
    If '$ISOBJECT(bundle) {
        Return 0
    }

    Set entries = bundle.%Get("entry")
    If '$ISOBJECT(entries) {
        Return 0
    }

    Set needle = $ZCONVERT(keyword, "L")
    For i=0:1:(entries.%Size()-1) {
        Set item = entries.%Get(i)
        If '$ISOBJECT(item) {
            Continue
        }
        Set resource = item.%Get("resource")
        If '$ISOBJECT(resource) {
            Continue
        }

        Set codeObj = resource.%Get("code")
        Set text = $ZCONVERT(..GetSafeText(codeObj, "text"), "L")
        If text [ needle {
            Return 1
        }

        Set coding = ""
        If $ISOBJECT(codeObj) {
            Set coding = codeObj.%Get("coding")
        }
        If $ISOBJECT(coding) {
            For j=0:1:(coding.%Size()-1) {
                Set c = coding.%Get(j)
                If '$ISOBJECT(c) {
                    Continue
                }
                Set display = $ZCONVERT(..GetSafeText(c, "display"), "L")
                Set code = $ZCONVERT(..GetSafeText(c, "code"), "L")
                If (display [ needle) || (code [ needle) {
                    Return 1
                }
            }
        }
    }

    Return 0
}

ClassMethod HasFamilyHistorySkinCancer(context As %DynamicObject) As %Boolean [ Internal ]
{
    If '$ISOBJECT(context) {
        Return 0
    }

    Set bundle = context.%Get("familyHistory")
    If '$ISOBJECT(bundle) {
        Return 0
    }

    Set entries = bundle.%Get("entry")
    If '$ISOBJECT(entries) {
        Return 0
    }

    For i=0:1:(entries.%Size()-1) {
        Set item = entries.%Get(i)
        If '$ISOBJECT(item) {
            Continue
        }
        Set resource = item.%Get("resource")
        If '$ISOBJECT(resource) {
            Continue
        }

        Set conditions = resource.%Get("condition")
        If '$ISOBJECT(conditions) {
            Continue
        }

        For j=0:1:(conditions.%Size()-1) {
            Set c = conditions.%Get(j)
            If '$ISOBJECT(c) {
                Continue
            }

            Set codeObj = c.%Get("code")
            Set text = $ZCONVERT(..GetSafeText(codeObj, "text"), "L")
            If (text [ "skin cancer") || (text [ "melanoma") {
                Return 1
            }

            Set coding = ""
            If $ISOBJECT(codeObj) {
                Set coding = codeObj.%Get("coding")
            }
            If $ISOBJECT(coding) {
                For k=0:1:(coding.%Size()-1) {
                    Set one = coding.%Get(k)
                    If '$ISOBJECT(one) {
                        Continue
                    }
                    Set display = $ZCONVERT(..GetSafeText(one, "display"), "L")
                    Set code = $ZCONVERT(..GetSafeText(one, "code"), "L")
                    If (display [ "skin cancer") || (display [ "melanoma") || (code [ "melanoma") {
                        Return 1
                    }
                }
            }
        }
    }

    Return 0
}

ClassMethod BuildRecentResults(items As %DynamicArray) As %DynamicArray [ Internal ]
{
    Set out = []

    If '$ISOBJECT(items) || (items.%Size()=0) {
        Do out.%Push("No lab data available in the selected panel.")
        Return out
    }

    For i=0:1:(items.%Size()-1) {
        Set it = items.%Get(i)
        If '$ISOBJECT(it) {
            Continue
        }
        Set count = +it.%Get("pointCount")
        If count=0 {
            Continue
        }

        Set latest = it.%Get("latest")
        If '$ISOBJECT(latest) {
            Continue
        }

        Set label = ..GetSafeText(it, "label")
        Set value = latest.%Get("value")
        Set unit = ..GetSafeText(latest, "unit")
        Set status = ..HumanizeStatus(..GetSafeText(it, "status"))
        Do out.%Push(label _ ": " _ value _ " " _ unit _ " (" _ status _ ")")
    }

    If out.%Size()=0 {
        Do out.%Push("No numeric lab values were found for this panel.")
    }

    Return out
}

ClassMethod BuildTrendLines(items As %DynamicArray) As %DynamicArray [ Internal ]
{
    Set out = []

    If '$ISOBJECT(items) || (items.%Size()=0) {
        Do out.%Push("Trend information is not available.")
        Return out
    }

    For i=0:1:(items.%Size()-1) {
        Set it = items.%Get(i)
        If '$ISOBJECT(it) {
            Continue
        }

        Set count = +it.%Get("pointCount")
        If count<2 {
            Continue
        }

        Set label = ..GetSafeText(it, "label")
        Set dir = ..GetSafeText(it, "trendDirection")
        Set delta = +it.%Get("delta")
        Set unit = ..GetSafeText(it, "unit")

        If dir = "up" {
            Do out.%Push(label _ " increased by " _ delta _ " " _ unit _ " since the prior result.")
        } ElseIf dir = "down" {
            Do out.%Push(label _ " decreased by " _ $ZABS(delta) _ " " _ unit _ " since the prior result.")
        } Else {
            Do out.%Push(label _ " is stable compared with the prior result.")
        }
    }

    If out.%Size()=0 {
        Do out.%Push("Only one or no value is available, so trend comparison is limited.")
    }

    Return out
}

ClassMethod AppendLines(ByRef target As %DynamicArray, source As %DynamicArray) [ Internal ]
{
    If '$ISOBJECT(target) {
        Quit
    }
    If '$ISOBJECT(source) {
        Quit
    }
    For i=0:1:(source.%Size()-1) {
        Set line = source.%Get(i)
        If line = "" {
            Continue
        }
        Do target.%Push(line)
    }
}

ClassMethod BuildActiveInfectionResultLines(context As %DynamicObject, withinDays As %Integer = 60) As %DynamicArray [ Internal ]
{
    Set out = []
    Set findings = ..CollectActiveInfectionFindings(context, withinDays)
    If '$ISOBJECT(findings) {
        Return out
    }

    For i=0:1:(findings.%Size()-1) {
        Set f = findings.%Get(i)
        If '$ISOBJECT(f) {
            Continue
        }
        Set name = ..GetSafeText(f, "name")
        Set kind = ..GetSafeText(f, "kind")
        If name = "" {
            Continue
        }
        If kind = "virus" {
            Do out.%Push("Recent infection testing: " _ name _ " was reported as positive.")
        } Else {
            Do out.%Push("Recent infection testing: " _ name _ " was reported as positive.")
        }
    }

    Return out
}

ClassMethod BuildActiveInfectionMeaningLines(context As %DynamicObject, withinDays As %Integer = 60) As %DynamicArray [ Internal ]
{
    Set out = []
    Set findings = ..CollectActiveInfectionFindings(context, withinDays)
    If '$ISOBJECT(findings) {
        Return out
    }

    For i=0:1:(findings.%Size()-1) {
        Set f = findings.%Get(i)
        If '$ISOBJECT(f) {
            Continue
        }
        Set name = ..GetSafeText(f, "name")
        Set kind = ..GetSafeText(f, "kind")
        If name = "" {
            Continue
        }

        Set msg = "Infection result - " _ name _ ": this infection was reported positive in recent testing. "
        If kind = "virus" {
            Set msg = msg _ ..GetVirusBodyImpactGuidance(name) _ " " _ ..GetVirusTransmissionGuidance(name)
        } Else {
            Set msg = msg _ ..GetNonVirusBodyImpactGuidance(name) _ " Transmission depends on the organism and exposure type. Ask your clinician what precautions and partner/contact steps are needed now."
        }
        Set msg = msg _ " Next step: follow treatment instructions and complete the recommended repeat tests."
        Do out.%Push(msg)
    }

    Return out
}

ClassMethod CollectActiveInfectionFindings(context As %DynamicObject, withinDays As %Integer = 60) As %DynamicArray [ Internal ]
{
    Set out = []
    Set bundle = ""
    Set entries = ""

    If '$ISOBJECT(context) {
        Return out
    }

    Set bundle = context.%Get("diagnosticReports")
    If '$ISOBJECT(bundle) {
        Return out
    }

    Set entries = bundle.%Get("entry")
    If '$ISOBJECT(entries) {
        Return out
    }

    For i=0:1:(entries.%Size()-1) {
        Set item = entries.%Get(i)
        If '$ISOBJECT(item) {
            Continue
        }
        Set resource = item.%Get("resource")
        If '$ISOBJECT(resource) {
            Continue
        }
        If '..IsDiagnosticReportRecent(resource, withinDays) {
            Continue
        }

        Set txt = ..GetSafeText(resource, "conclusion")
        Set codeObj = resource.%Get("code")
        If $ISOBJECT(codeObj) {
            Set codeText = ..GetSafeText(codeObj, "text")
            If codeText '= "" {
                Set txt = txt _ " " _ codeText
            }
        }
        If txt = "" {
            Continue
        }

        Do ..AddInfectionFindingsFromText(.out, txt)
    }

    Return out
}

ClassMethod IsDiagnosticReportRecent(resource As %DynamicObject, withinDays As %Integer = 60) As %Boolean [ Internal ]
{
    Set today = +$PIECE($HOROLOG, ",", 1)
    Set d = ..GetSafeText(resource, "effectiveDateTime")
    If d = "" {
        Set d = ..GetSafeText(resource, "issued")
    }
    If d = "" {
        // If the report has no date, keep it visible instead of silently dropping it.
        Return 1
    }

    Set h = ..FHIRDateToH(d)
    If h = "" {
        Return 1
    }

    Set diff = today-h
    If (diff>=0) && (diff<=withinDays) {
        Return 1
    }
    Return 0
}

ClassMethod AddInfectionFindingsFromText(ByRef out As %DynamicArray, text As %String) [ Internal ]
{
    Set t = $ZCONVERT(text, "L")
    If (t '[ "positive") && (t '[ "detected") && (t '[ "reactive") {
        Quit
    }

    Do ..TryAddPathogenFinding(.out, t, "covid", "COVID-19", "virus")
    Do ..TryAddPathogenFinding(.out, t, "sars", "SARS-CoV-2", "virus")
    Do ..TryAddPathogenFinding(.out, t, "influenza", "Influenza", "virus")
    Do ..TryAddPathogenFinding(.out, t, "flu", "Influenza", "virus")
    Do ..TryAddPathogenFinding(.out, t, "rsv", "RSV", "virus")
    Do ..TryAddPathogenFinding(.out, t, "adenovirus", "Adenovirus", "virus")
    Do ..TryAddPathogenFinding(.out, t, "norovirus", "Norovirus", "virus")
    Do ..TryAddPathogenFinding(.out, t, "rotavirus", "Rotavirus", "virus")
    Do ..TryAddPathogenFinding(.out, t, "herpes", "Herpes", "virus")
    Do ..TryAddPathogenFinding(.out, t, "hpv", "HPV", "virus")
    Do ..TryAddPathogenFinding(.out, t, "hiv", "HIV", "virus")
    Do ..TryAddPathogenFinding(.out, t, "hepatitis b", "Hepatitis B", "virus")
    Do ..TryAddPathogenFinding(.out, t, "hepatitis c", "Hepatitis C", "virus")
    Do ..TryAddPathogenFinding(.out, t, "ebv", "EBV", "virus")
    Do ..TryAddPathogenFinding(.out, t, "cmv", "CMV", "virus")

    Do ..TryAddPathogenFinding(.out, t, "syphilis", "Syphilis", "infection")
    Do ..TryAddPathogenFinding(.out, t, "gonorrhea", "Gonorrhea", "infection")
    Do ..TryAddPathogenFinding(.out, t, "chlamydia", "Chlamydia", "infection")
    Do ..TryAddPathogenFinding(.out, t, "trichomon", "Trichomonas", "infection")

    If ((t [ "virus") || (t [ "viral")) && ((t [ "positive") || (t [ "detected") || (t [ "reactive")) {
        Do ..PushUniqueFinding(.out, "A recent viral test", "virus")
    }
}

ClassMethod TryAddPathogenFinding(ByRef out As %DynamicArray, textLower As %String, keyword As %String, displayName As %String, kind As %String) [ Internal ]
{
    If textLower '[ keyword {
        Quit
    }

    Set status = ..GetKeywordStatusNearText(textLower, keyword)
    If status '= "positive" {
        Quit
    }
    Do ..PushUniqueFinding(.out, displayName, kind)
}

ClassMethod GetKeywordStatusNearText(textLower As %String, keyword As %String) As %String [ Internal ]
{
    Set p = $FIND(textLower, keyword)
    If p=0 {
        Return ""
    }
    Set len = $LENGTH(textLower)
    Set afterStart = p
    Set afterEnd = p+90 If afterEnd>len Set afterEnd=len
    Set beforeStart = p-40 If beforeStart<1 Set beforeStart=1
    Set beforeEnd = p

    Set afterSeg = $EXTRACT(textLower, afterStart, afterEnd)
    Set beforeSeg = $EXTRACT(textLower, beforeStart, beforeEnd)

    Set posAfter = ..FindFirstStatusToken(afterSeg, "positive")
    Set negAfter = ..FindFirstStatusToken(afterSeg, "negative")

    If (posAfter>0) && ((negAfter=0) || (posAfter<negAfter)) {
        Return "positive"
    }
    If (negAfter>0) && ((posAfter=0) || (negAfter<posAfter)) {
        Return "negative"
    }

    Set posBefore = ..FindFirstStatusToken($REVERSE(beforeSeg), "positive")
    Set negBefore = ..FindFirstStatusToken($REVERSE(beforeSeg), "negative")
    If (posBefore>0) && ((negBefore=0) || (posBefore<negBefore)) {
        Return "positive"
    }
    If (negBefore>0) && ((posBefore=0) || (negBefore<posBefore)) {
        Return "negative"
    }

    Return ""
}

ClassMethod FindFirstStatusToken(segment As %String, mode As %String) As %Integer [ Internal ]
{
    If mode = "positive" {
        Set p1 = $FIND(segment, "positive")
        Set p2 = $FIND(segment, "detected")
        Set p3 = $FIND(segment, "reactive")
    } Else {
        Set p1 = $FIND(segment, "negative")
        Set p2 = $FIND(segment, "not detected")
        Set p3 = $FIND(segment, "non-reactive")
    }

    Set min = 0
    If p1>0 Set min=p1
    If (p2>0) && ((min=0) || (p2<min)) Set min=p2
    If (p3>0) && ((min=0) || (p3<min)) Set min=p3
    Return min
}

ClassMethod PushUniqueFinding(ByRef out As %DynamicArray, name As %String, kind As %String) [ Internal ]
{
    If '$ISOBJECT(out) {
        Quit
    }
    If name = "" {
        Quit
    }

    For i=0:1:(out.%Size()-1) {
        Set one = out.%Get(i)
        If '$ISOBJECT(one) {
            Continue
        }
        If ..GetSafeText(one, "name") = name {
            Quit
        }
    }

    Set o = {}
    Set o.name = name
    Set o.kind = kind
    Do out.%Push(o)
}

ClassMethod GetVirusTransmissionGuidance(name As %String) As %String [ Internal ]
{
    Set n = $ZCONVERT(name, "L")

    If (n [ "covid") || (n [ "sars") || (n [ "influenza") || (n [ "rsv") || (n [ "adenovirus") {
        Return "It can be passed to others mainly through respiratory droplets/aerosols and close contact, so masking when symptomatic, ventilation, and hand hygiene help reduce spread."
    }
    If (n [ "norovirus") || (n [ "rotavirus") {
        Return "It can be passed to others through stool-to-mouth transmission (for example contaminated hands, food, or surfaces), so strict hand hygiene and surface cleaning are important."
    }
    If n [ "hpv" {
        Return "It can be passed through close skin-to-skin sexual contact, including contact without visible symptoms, so partner protection and follow-up are important."
    }
    If n [ "herpes" {
        Return "It can be passed through direct skin or mucosal contact, including sexual contact, and risk is higher during active sores."
    }
    If (n [ "hiv") || (n [ "hepatitis b") || (n [ "hepatitis c") {
        Return "It can be passed through blood or sexual exposure (and in some cases perinatal exposure), so barrier protection and clinician-guided partner counseling are important."
    }

    Return "Many viruses can be passed to others through close contact, respiratory secretions, blood, sexual contact, or contaminated hands/surfaces depending on the virus; your clinician can confirm the exact route for this result."
}

ClassMethod GetVirusBodyImpactGuidance(name As %String) As %String [ Internal ]
{
    Set n = $ZCONVERT(name, "L")

    If (n [ "covid") || (n [ "sars") || (n [ "influenza") || (n [ "rsv") || (n [ "adenovirus") {
        Return "What this may mean physically: your immune system is likely actively fighting a respiratory viral infection, which can cause fever, fatigue, body aches, cough, sore throat, and shortness of breath."
    }
    If (n [ "norovirus") || (n [ "rotavirus") {
        Return "What this may mean physically: your gut may be inflamed, which can cause nausea, vomiting, diarrhea, dehydration, weakness, and dizziness."
    }
    If n [ "hpv" {
        Return "What this may mean physically: many people have no immediate symptoms, but persistent infection can cause cell changes that need follow-up screening."
    }
    If n [ "herpes" {
        Return "What this may mean physically: symptoms can include painful blisters or sores, burning, and local tenderness, with flare-ups over time."
    }
    If n [ "hiv" {
        Return "What this may mean physically: untreated infection can weaken immune defense over time, increasing risk of repeated or severe infections."
    }
    If (n [ "hepatitis b") || (n [ "hepatitis c") {
        Return "What this may mean physically: liver inflammation may be present, and over time this can increase risk of liver scarring if untreated."
    }

    Return "What this may mean physically: your body is likely mounting an immune response to a viral infection, which can cause fatigue, weakness, fever, and inflammation-related symptoms depending on the organ involved."
}

ClassMethod GetNonVirusBodyImpactGuidance(name As %String) As %String [ Internal ]
{
    Set n = $ZCONVERT(name, "L")
    If n [ "syphilis" {
        Return "What this may mean physically: symptoms vary by stage and can include sores, rash, swollen lymph nodes, and systemic symptoms; untreated infection can affect multiple organs over time."
    }
    If (n [ "gonorrhea") || (n [ "chlamydia") || (n [ "trichomon") {
        Return "What this may mean physically: infection may cause genital irritation, discharge, pain with urination, pelvic pain, or no symptoms at all, with potential reproductive complications if untreated."
    }
    Return "What this may mean physically: active infection can cause inflammation, fatigue, fever, and organ-specific symptoms depending on where the infection is located."
}

ClassMethod BuildInflammationMeaningLines(context As %DynamicObject = "") As %DynamicArray [ Internal ]
{
    Set out = []
    If '$ISOBJECT(context) {
        Return out
    }

    Set crp = "", cu = ""
    If ..TryGetLatestObsValueByLoinc(context, "inflammationNutrition", "1988-5", .crp, .cu) {
        If +crp>=10 {
            Do out.%Push("CRP: is elevated at " _ crp _ " " _ cu _ ". What this may mean physically: your body is likely in an active inflammatory state, often from infection, and this can match symptoms like fatigue, weakness, fever, body aches, and feeling generally unwell. Next step: review likely infection source and reassess CRP with follow-up.")
        } ElseIf +crp>3 {
            Do out.%Push("CRP: is mildly elevated at " _ crp _ " " _ cu _ ". What this may mean physically: low-grade inflammation may be present and can contribute to feeling tired or unwell. Next step: interpret together with symptoms and repeat if clinically needed.")
        }
    }

    Return out
}

ClassMethod BuildMeaningLines(panel As %String, items As %DynamicArray, context As %DynamicObject = "") As %DynamicArray [ Internal ]
{
    Set out = []

    If '$ISOBJECT(items) || (items.%Size()=0) {
        Do out.%Push("No clinical interpretation can be generated from missing data.")
        Return out
    }

    For i=0:1:(items.%Size()-1) {
        Set it = items.%Get(i)
        If '$ISOBJECT(it) {
            Continue
        }

        Set count = +it.%Get("pointCount")
        If count=0 {
            Continue
        }

        Set label = ..GetSafeText(it, "label")
        Set code = ..GetSafeText(it, "code")
        Set status = ..GetSafeText(it, "status")

        Set statusLine = ""
        If status = "high" {
            Set statusLine = "is above the usual range"
        } ElseIf status = "low" {
            Set statusLine = "is below the usual range"
        } ElseIf status = "in-range" {
            Set statusLine = "is in the usual range"
        } Else {
            Set statusLine = "was measured"
        }

        Set simple = ..GetSimpleLabExplanation(code, label)
        Set combined = label _ ": " _ statusLine _ "."
        If simple '= "" {
            Set combined = combined _ " " _ simple
        }

        // Add one action-oriented sentence so patients don't need to interpret on their own.
        If status = "high" {
            Set combined = combined _ " Next step: review possible causes and timing for repeat testing with your doctor."
        } ElseIf status = "low" {
            Set combined = combined _ " Next step: review likely causes and whether nutrition, medications, or follow-up tests are needed."
        } ElseIf status = "in-range" {
            Set combined = combined _ " Next step: continue your current plan and routine follow-up."
        }

        Do out.%Push(combined)
    }

    If out.%Size()=0 {
        Do out.%Push("No interpretable values were found for this panel.")
    }

    Return out
}

ClassMethod GetSimpleLabExplanation(code As %String, label As %String) As %String [ Internal ]
{
    If code = "1751-7" {
        Return "Albumin is a protein made by your liver. It can reflect nutrition status, inflammation, and fluid balance."
    }
    If code = "17861-6" {
        Return "Calcium helps bones, muscles, and nerves work well."
    }
    If code = "2339-0" {
        Return "Glucose is your blood sugar level at the time of the blood draw."
    }
    If code = "1975-2" {
        Return "Bilirubin reflects how your body processes red blood cell breakdown and bile flow."
    }
    If code = "3094-0" {
        Return "BUN is a waste marker that can rise with dehydration or kidney stress."
    }
    If code = "2160-0" {
        Return "Creatinine is a kidney-related waste marker used to estimate kidney function."
    }
    If code = "1989-3" {
        Return "Vitamin D supports bone health and calcium balance."
    }
    If code = "4548-4" {
        Return "A1c shows your average blood sugar over about the last 3 months."
    }
    If code = "13457-7" {
        Return "LDL is often called bad cholesterol because higher values are linked to more heart and stroke risk."
    }
    If code = "2085-9" {
        Return "HDL is often called good cholesterol because it helps remove excess cholesterol from blood vessels."
    }
    If code = "718-7" {
        Return "Hemoglobin carries oxygen in your red blood cells."
    }
    If code = "6690-2" {
        Return "White blood cells help your body fight infection and inflammation."
    }
    If code = "777-3" {
        Return "Platelets help your blood clot and stop bleeding."
    }
    If code = "4544-3" {
        Return "Hematocrit is the percent of your blood made up of red blood cells."
    }

    If label '= "" {
        Return "This test gives information about how your body is functioning and is interpreted together with your symptoms and other labs."
    }
    Return ""
}

ClassMethod BuildHelpfulLines(guidance As %DynamicObject) As %DynamicArray [ Internal ]
{
    Set out = []
    If '$ISOBJECT(guidance) {
        Do out.%Push("Educational guidance is currently unavailable.")
        Return out
    }

    Set snippets = guidance.%Get("snippets")
    If '$ISOBJECT(snippets) || (snippets.%Size()=0) {
        Do out.%Push("Educational guidance is currently unavailable.")
        Return out
    }

    For i=0:1:(snippets.%Size()-1) {
        Set s = snippets.%Get(i)
        If '$ISOBJECT(s) {
            Continue
        }
        Set text = ..GetSafeText(s, "text")
        Set source = ..GetSafeText(s, "source")
        If text = "" {
            Continue
        }
        If ..IsDefinitionLikeText(text) {
            Continue
        }
        If source '= "" {
            Do out.%Push(text _ " [source: " _ source _ "]")
        } Else {
            Do out.%Push(text)
        }
    }

    If out.%Size()=0 {
        Do out.%Push("Educational guidance is currently unavailable.")
    }

    Return out
}

ClassMethod IsDefinitionLikeText(text As %String) As %Boolean [ Internal ]
{
    Set t = $ZCONVERT(text, "L")
    If t [ "often called bad cholesterol" Return 1
    If t [ "often called good cholesterol" Return 1
    If t [ "a1c estimates average blood sugar" Return 1
    If t [ "creatinine is used to estimate kidney" Return 1
    If t [ "hemoglobin carries oxygen" Return 1
    If t [ "white blood cells help fight infection" Return 1
    Return 0
}

ClassMethod BuildQuestionLines(panel As %String, items As %DynamicArray) As %DynamicArray [ Internal ]
{
    Set out = []

    If panel = "a1c" {
        Do out.%Push("Is my A1c target right for my age and health conditions?")
        Do out.%Push("What specific change would most improve my next A1c result?")
        Return out
    }

    If panel = "lipids" {
        Do out.%Push("Which cholesterol number should we focus on most right now?")
        Do out.%Push("Do I need medication changes or lifestyle changes first?")
        Return out
    }

    If panel = "cbc" {
        Do out.%Push("Do these blood count changes need repeat testing soon?")
        Do out.%Push("Could my symptoms be related to these blood count results?")
        Return out
    }

    If panel = "cmp" {
        Do out.%Push("Which values in my comprehensive metabolic panel are most important for me right now?")
        Do out.%Push("Could dehydration, diet, or medications explain these changes?")
        Return out
    }

    Do out.%Push("What changed since my last test?")
    Do out.%Push("When should I repeat this lab panel?")
    Return out
}

ClassMethod BuildNextStep(items As %DynamicArray, context As %DynamicObject = "") As %String [ Internal ]
{
    Set hasHighRisk = 0
    Set hasTrendWorse = 0
    Set hasCriticalRisk = 0

    If $ISOBJECT(items) {
        For i=0:1:(items.%Size()-1) {
            Set it = items.%Get(i)
            If '$ISOBJECT(it) {
                Continue
            }
            Set status = ..GetSafeText(it, "status")
            Set dir = ..GetSafeText(it, "trendDirection")
            If ..IsCriticalLabRisk(it) {
                Set hasCriticalRisk = 1
            }
            If (status = "high") || (status = "low") {
                Set hasHighRisk = 1
            }
            If (status = "high") && (dir = "up") {
                Set hasTrendWorse = 1
            }
            If (status = "low") && (dir = "down") {
                Set hasTrendWorse = 1
            }
        }
    }

    If hasCriticalRisk && ..HasSevereSymptomSignals(context) {
        Return "These results may represent a medical emergency with high immediate risk. Call local emergency services now or go to the nearest hospital emergency department immediately."
    }
    If hasCriticalRisk {
        Return "These results may represent a medical emergency. Contact your clinician immediately or go to the nearest hospital emergency department now, especially if you feel very unwell."
    }
    If hasTrendWorse {
        Return "Schedule follow-up soon to review worsening lab trends and agree on a treatment plan."
    }
    If hasHighRisk {
        Return "Review these abnormal values with your doctor and confirm timing for repeat labs."
    }
    Return "Continue your current plan and confirm the next routine lab check date."
}

ClassMethod IsCriticalLabRisk(item As %DynamicObject) As %Boolean [ Internal ]
{
    If '$ISOBJECT(item) {
        Return 0
    }

    Set latest = item.%Get("latest")
    If '$ISOBJECT(latest) {
        Return 0
    }

    Set value = +..GetSafeText(latest, "value")
    Set code = ..GetSafeText(item, "code")
    Set low = +..GetSafeText(item, "low")
    Set high = +..GetSafeText(item, "high")
    Set status = ..GetSafeText(item, "status")

    If (code = "718-7") && (value<7.0) Return 1
    If (code = "4544-3") && (value<21.0) Return 1
    If (code = "6690-2") && ((value<1.5) || (value>30.0)) Return 1
    If (code = "777-3") && ((value<20) || (value>1000)) Return 1
    If (code = "2823-3") && ((value<2.8) || (value>6.2)) Return 1
    If (code = "2951-2") && ((value<125) || (value>155)) Return 1
    If (code = "2339-0") && ((value<50) || (value>400)) Return 1
    If (code = "2160-0") && (value>4.0) Return 1

    // Generic safeguard: very large departures from reference range are treated as critical.
    If (status = "low") && (low>0) && (value<((0.7*low))) Return 1
    If (status = "high") && (high>0) && (value>((1.8*high))) Return 1

    Return 0
}

ClassMethod HasSevereSymptomSignals(context As %DynamicObject = "") As %Boolean [ Internal ]
{
    If '$ISOBJECT(context) {
        Return 0
    }

    If ..HasConditionKeyword(context, "severe") Return 1
    If ..HasConditionKeyword(context, "shortness of breath") Return 1
    If ..HasConditionKeyword(context, "chest pain") Return 1
    If ..HasConditionKeyword(context, "confusion") Return 1
    If ..HasConditionKeyword(context, "faint") Return 1
    If ..HasConditionKeyword(context, "syncope") Return 1
    If ..HasConditionKeyword(context, "dizziness") Return 1
    If ..HasConditionKeyword(context, "weakness") Return 1

    If ..HasDiagnosticReportKeyword(context, "severe") Return 1
    If ..HasDiagnosticReportKeyword(context, "respiratory distress") Return 1
    If ..HasDiagnosticReportKeyword(context, "shock") Return 1

    Set temp = "", tu = ""
    If ..TryGetLatestObsValueByLoinc(context, "vitalBody", "8310-5", .temp, .tu) {
        If +temp>=39.0 Return 1
    }

    Set hr = "", hu = ""
    If ..TryGetLatestObsValueByLoinc(context, "vitalBody", "8867-4", .hr, .hu) {
        If +hr>=120 Return 1
    }

    Set spo2 = "", su = ""
    If ..TryGetLatestObsValueByLoinc(context, "vitalBody", "59408-5", .spo2, .su) {
        If +spo2<90 Return 1
    }

    If ..ContextBundleContains(context, "encounters", "emergency") Return 1

    Return 0
}

ClassMethod BuildGuidanceQuery(panel As %String, items As %DynamicArray) As %String [ Internal ]
{
    Set q = "patient friendly explanation for " _ panel _ " results"

    If $ISOBJECT(items) && (items.%Size()>0) {
        For i=0:1:(items.%Size()-1) {
            Set it = items.%Get(i)
            If '$ISOBJECT(it) {
                Continue
            }
            Set status = ..GetSafeText(it, "status")
            Set label = ..GetSafeText(it, "label")
            If (status = "high") || (status = "low") {
                Set q = q _ " " _ label _ " " _ status
                Quit
            }
        }
    }

    Return q
}

ClassMethod HumanizeStatus(status As %String) As %String [ Internal ]
{
    If status = "in-range" Return "in range"
    If status = "no-data" Return "no data"
    If status = "high-good" Return "higher than range"
    Return status
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
