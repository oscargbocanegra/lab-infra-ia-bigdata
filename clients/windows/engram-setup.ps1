# Configure one Windows Engram client for the private cloud pilot.
[CmdletBinding()]
param(
  [string[]]$Project = @("engram-pilot"),
  [string]$Server = "https://aifabric.engram"
)
$ErrorActionPreference = "Stop"
$token = Read-Host "Engram Bearer token" -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($token)
try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
if ([string]::IsNullOrWhiteSpace($plain)) { throw "Token vacío" }
[Environment]::SetEnvironmentVariable("ENGRAM_CLOUD_AUTOSYNC", "1", "User")
[Environment]::SetEnvironmentVariable("ENGRAM_CLOUD_SERVER", $Server, "User")
[Environment]::SetEnvironmentVariable("ENGRAM_CLOUD_TOKEN", $plain, "User")
$env:ENGRAM_CLOUD_AUTOSYNC = "1"
$env:ENGRAM_CLOUD_SERVER = $Server
$env:ENGRAM_CLOUD_TOKEN = $plain
foreach ($p in $Project) {
  Write-Host "Enrolling project $p against $Server"
  & engram cloud enroll $p
  if ($LASTEXITCODE -ne 0) { throw "No se pudo inscribir el proyecto $p (exit code $LASTEXITCODE)" }
  & engram sync --cloud --project $p
  if ($LASTEXITCODE -ne 0) { throw "Falló la sincronización del proyecto $p (exit code $LASTEXITCODE). Verifica la CA TLS y vuelve a ejecutar." }
}
Remove-Variable plain -ErrorAction SilentlyContinue
Write-Host "Engram client configured. Restart Codex so its local MCP process inherits the environment."
