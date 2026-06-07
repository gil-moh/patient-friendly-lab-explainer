@echo off
setlocal

set MAC=%TEMP%\patient_lab_explainer_quality.mac

> "%MAC%" echo zn "USER"
>> "%MAC%" echo set sc=##class(Sample.AI.Examples.PatientLabQualityChecks).RunSyntheticChecks^(^)
>> "%MAC%" echo write !,"QUALITY_STATUS=",$system.Status.GetOneErrorText^(sc^),!
>> "%MAC%" echo halt

type "%MAC%" | docker exec -i patient-friendly-lab-explainer-iris-1 iris session IRIS

endlocal
