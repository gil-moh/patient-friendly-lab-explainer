$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'demo_outputs'
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

$macro = @'
zn "USER"
set ^||ENV("FHIR_BASE_URL")="http://host.docker.internal:52773/fhir/r4"
set ^||ENV("FHIR_BASIC_USER")="_SYSTEM"
set ^||ENV("FHIR_BASIC_PASS")="SYS"
set sc1=##class(Sample.AI.Examples.PatientLabExplainerDemo).DemoToFile("demo-rich-003","a1c","/tmp/patient-lab-a1c.txt",1)
write !,"A1C=",$system.Status.GetOneErrorText(sc1),!
set sc2=##class(Sample.AI.Examples.PatientLabExplainerDemo).DemoToFile("demo-rich-003","lipids","/tmp/patient-lab-lipids.txt",1)
write !,"LIPIDS=",$system.Status.GetOneErrorText(sc2),!
set sc3=##class(Sample.AI.Examples.PatientLabExplainerDemo).DemoToFile("demo-rich-003","cmp","/tmp/patient-lab-cmp.txt",1)
write !,"CMP=",$system.Status.GetOneErrorText(sc3),!
halt
'@

$macroFile = Join-Path $env:TEMP 'patient_lab_explainer_run_all.mac'
Set-Content -Path $macroFile -Value $macro -Encoding ascii
Get-Content -Raw $macroFile | docker exec -i iris-ai-hub-162 iris session IRIS

docker cp iris-ai-hub-162:/tmp/patient-lab-a1c.txt (Join-Path $outDir 'patient-lab-a1c.txt') | Out-Null
docker cp iris-ai-hub-162:/tmp/patient-lab-lipids.txt (Join-Path $outDir 'patient-lab-lipids.txt') | Out-Null
docker cp iris-ai-hub-162:/tmp/patient-lab-cmp.txt (Join-Path $outDir 'patient-lab-cmp.txt') | Out-Null

Write-Host "Generated artifacts:"
Write-Host "- $outDir\patient-lab-a1c.txt"
Write-Host "- $outDir\patient-lab-lipids.txt"
Write-Host "- $outDir\patient-lab-cmp.txt"
