param(
    [string]$MacroPath = "C:\Projects\FHIR\tmp_validation\macros\tmp_show_various_outputs.mac",
    [string]$Container = "iris-ai-hub-162"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $MacroPath)) {
    throw "Macro file not found: $MacroPath"
}

$macroContent = Get-Content -Raw $MacroPath

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "docker"
$psi.Arguments = "exec -i $Container iris session IRIS"
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
$null = $proc.Start()

$stdin = $proc.StandardInput
$stdin.Write($macroContent)
$stdin.Close()

$blankCount = 0
while (-not $proc.StandardOutput.EndOfStream) {
    $line = $proc.StandardOutput.ReadLine()

    # Match prior project behavior: suppress IRIS banner/prompt noise.
    if ($line -match '^\s*Node:\s') { continue }
    if ($line -match '^\s*USER>\s*$') { continue }

    if ($line -match '^\s*$') {
        $blankCount++
        if ($blankCount -le 1) {
            Write-Output ""
        }
        continue
    }

    $blankCount = 0
    Write-Output $line
}

$stderr = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()

if ($proc.ExitCode -ne 0) {
    if ($stderr -ne "") {
        Write-Error $stderr
    }
    throw "docker exec exited with code $($proc.ExitCode)"
}
