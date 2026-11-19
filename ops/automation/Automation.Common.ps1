#requires -Version 7.5
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if (-not ('MarketBrainRelayClient' -as [type])) {
    Add-Type -ReferencedAssemblies ([AppContext]::GetData('TRUSTED_PLATFORM_ASSEMBLIES').Split([IO.Path]::PathSeparator)) -TypeDefinition @'
using System;
using System.Net.Http;
using System.Security.Cryptography;
public static class MarketBrainRelayClient {
  public static HttpClient Create(string pin) {
    var h = new HttpClientHandler { AllowAutoRedirect = false, UseProxy = true };
    h.ServerCertificateCustomValidationCallback = (request, cert, chain, errors) =>
      cert != null && DateTime.UtcNow >= cert.NotBefore.ToUniversalTime() &&
      DateTime.UtcNow <= cert.NotAfter.ToUniversalTime() &&
      Convert.ToHexString(SHA256.HashData(cert.RawData)) == pin;
    return new HttpClient(h) { Timeout = TimeSpan.FromSeconds(15), MaxResponseContentBufferSize = 262144 };
  }
}
'@
}
function Get-AutomationConfig([string]$Path) {
    $cipher = Get-Content -LiteralPath $Path -Raw
    $secure = ConvertTo-SecureString $cipher
    $plain = [System.Net.NetworkCredential]::new('', $secure).Password
    $config = $plain | ConvertFrom-Json -DateKind String
    $plain = $null
    if ($config.url -notmatch '^https://[a-zA-Z0-9.-]+:18443$' -or $config.pin -notmatch '^[A-F0-9]{64}$' -or $config.token -notmatch '^[a-f0-9]{64}$' -or $config.role -notin @('controller','worker')) { throw 'Invalid pairing configuration' }
    return $config
}
function Invoke-AutomationApi($Config,[string]$Route,$Body) {
    $client = [MarketBrainRelayClient]::Create($Config.pin)
    try {
        $client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer',$Config.token)
        $content = [System.Net.Http.StringContent]::new(($Body | ConvertTo-Json -Depth 12 -Compress),[Text.Encoding]::UTF8,'application/json')
        try {
            $response = $client.PostAsync($Config.url + $Route,$content).GetAwaiter().GetResult()
            try {
                if (-not $response.IsSuccessStatusCode) { throw "Relay returned HTTP $([int]$response.StatusCode)" }
                return ($response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json -DateKind String)
            } finally { $response.Dispose() }
        } finally { $content.Dispose() }
    } finally { $client.Dispose() }
}
function Write-AutomationState([string]$Path,$Value) {
    $temporary = $Path + '.new'
    [IO.File]::WriteAllText($temporary,($Value | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temporary,$Path,$true)
}
