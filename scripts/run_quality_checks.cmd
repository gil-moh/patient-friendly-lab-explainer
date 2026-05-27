@echo off
setlocal

set MAC=%TEMP%\patient_lab_explainer_quality.mac

> "%MAC%" echo zn "USER"
>> "%MAC%" echo set sc=##class(Sample.AI.Examples.PatientLabQualityChecks).RunSyntheticChecks^(^)
>> "%MAC%" echo write !,"QUALITY_STATUS=",$system.Status.GetOneErrorText^(sc^),!
>> "%MAC%" echo halt

type "%MAC%" | docker exec -i iris-ai-hub-162 iris session IRIS

endlocal
