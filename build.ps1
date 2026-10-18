# Gera pihole_blocklist.txt: junta as listas de sources.txt, remove o que estiver em allowlist.txt,
# remove duplicados e subdominios redundantes, e grava no formato Adblock (||dominio^) para o Pi-hole.
# Funciona no Windows PowerShell 5.1 e no PowerShell 7 (GitHub Actions).
param(
    [string]$Sources   = (Join-Path $PSScriptRoot 'sources.txt'),
    [string]$Allowlist = (Join-Path $PSScriptRoot 'allowlist.txt'),
    [string]$Output    = (Join-Path $PSScriptRoot 'pihole_blocklist.txt'),
    [string]$ExcludedReport = ''
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Read-ConfigLines([string]$path) {
    Get-Content $path | ForEach-Object { ($_ -replace '#.*$', '').Trim() } | Where-Object { $_ }
}

# ---- allowlist ----
$allowExact = New-Object 'System.Collections.Generic.HashSet[string]'
$brands = New-Object 'System.Collections.Generic.List[string]'
foreach ($entry in Read-ConfigLines $Allowlist) {
    $entry = $entry.ToLowerInvariant()
    if ($entry.EndsWith('.*')) { $brands.Add([regex]::Escape($entry.Substring(0, $entry.Length - 2))) }
    else { [void]$allowExact.Add($entry) }
}
# TLDs aceitos em "marca.*". Lista fechada de proposito: TLDs exoticos (ex.: alibaba.ir, amazon.co.bi)
# costumam ser imitacoes/golpes que as listas de ameaca bloqueiam e nao devem ser liberados.
$brandTlds = @('com', 'net', 'org', 'br', 'com.br', 'us', 'ca', 'mx', 'com.mx', 'ar', 'com.ar', 'cl', 'co', 'com.co',
    'pe', 'com.pe', 'uy', 'com.uy', 'py', 'com.py', 'bo', 'com.bo', 'ec', 'com.ec', 've', 'com.ve', 'co.ve',
    'pt', 'es', 'fr', 'de', 'it', 'nl', 'be', 'ch', 'uk', 'co.uk', 'ie', 'pl', 'se', 'jp', 'co.jp', 'in', 'co.in',
    'com.au', 'sg', 'com.sg', 'cn', 'com.cn', 'com.tr', 'ru', 'ae', 'sa', 'com.sa')
$brandRegex = $null
if ($brands.Count -gt 0) {
    $tld = '(' + (($brandTlds | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')'
    $brandRegex = New-Object regex ("(^|\.)(" + ($brands -join '|') + ")\.$tld$"), 'Compiled'
}

function Test-Allowed([string]$domain) {
    $d = $domain
    while ($true) {
        if ($allowExact.Contains($d)) { return $true }
        $i = $d.IndexOf('.')
        if ($i -lt 0) { break }
        $d = $d.Substring($i + 1)
    }
    return ($null -ne $brandRegex -and $brandRegex.IsMatch($domain))
}

# ---- download + parse ----
$domainRegex = New-Object regex '^[a-z0-9_-]+(\.[a-z0-9_-]+)*\.[a-z][a-z0-9-]*$', 'Compiled'
$skip = @('localhost', 'localhost.localdomain', 'local', 'broadcasthost', 'ip6-localhost', 'ip6-loopback', '0.0.0.0')
$all = New-Object 'System.Collections.Generic.HashSet[string]'
$excluded = New-Object 'System.Collections.Generic.HashSet[string]'
$sourceUrls = @(Read-ConfigLines $Sources)
$client = New-Object System.Net.WebClient
$client.Encoding = [Text.Encoding]::UTF8

foreach ($url in $sourceUrls) {
    $text = $client.DownloadString($url)
    $count = 0
    foreach ($raw in $text.Split("`n")) {
        $line = $raw.Trim().ToLowerInvariant()
        if ($line.Length -eq 0 -or $line[0] -eq '!' -or $line[0] -eq '#' -or $line[0] -eq '[') { continue }
        $line = ($line -replace '\s#.*$', '').Trim()
        if ($line.StartsWith('||')) {
            # so regras simples ||dominio^ (sem modificadores, curingas ou caminhos)
            if (-not $line.EndsWith('^')) { continue }
            $d = $line.Substring(2, $line.Length - 3)
        } elseif ($line -match '^(0\.0\.0\.0|127\.0\.0\.1|::1?)\s+(\S+)$') {
            $d = $Matches[2]
        } elseif ($line -notmatch '\s') {
            $d = $line
        } else { continue }
        if ($skip -contains $d -or -not $domainRegex.IsMatch($d)) { continue }
        if (Test-Allowed $d) { [void]$excluded.Add($d); continue }
        if ($all.Add($d)) { $count++ }
    }
    if ($count -eq 0) { throw "Nenhum dominio lido de $url - abortando para nao publicar lista vazia." }
    Write-Host ("{0,8} novos  {1}" -f $count, $url)
}

# ---- remove subdominios ja cobertos por um dominio pai (||pai^ ja bloqueia os subdominios) ----
$final = New-Object 'System.Collections.Generic.List[string]'
foreach ($d in $all) {
    $p = $d; $covered = $false
    while (($i = $p.IndexOf('.')) -ge 0) {
        $p = $p.Substring($i + 1)
        if ($p.IndexOf('.') -lt 0) { break }
        if ($all.Contains($p)) { $covered = $true; break }
    }
    if (-not $covered) { $final.Add($d) }
}
$final.Sort([StringComparer]::Ordinal)

# ---- grava ----
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('! Title: phillypi - Pi-hole blocklist (sem Google/Google Ads e grandes lojas)')
[void]$sb.AppendLine('! Last modified: ' + (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC')
[void]$sb.AppendLine('! Expires: 1 day')
[void]$sb.AppendLine('! Domains: ' + $final.Count)
[void]$sb.AppendLine('! Excluded by allowlist: ' + $excluded.Count)
[void]$sb.AppendLine('! Sources:')
foreach ($u in $sourceUrls) { [void]$sb.AppendLine('!   ' + $u) }
[void]$sb.AppendLine('!')
foreach ($d in $final) { [void]$sb.Append('||').Append($d).Append("^`n") }
[IO.File]::WriteAllText($Output, $sb.ToString().Replace("`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))

if ($ExcludedReport) {
    $ex = New-Object 'System.Collections.Generic.List[string]' (,[string[]]@($excluded))
    $ex.Sort([StringComparer]::Ordinal)
    [IO.File]::WriteAllLines($ExcludedReport, $ex)
}
Write-Host ("Total: {0} dominios ({1} unicos antes da compactacao, {2} removidos pela allowlist) -> {3}" -f $final.Count, $all.Count, $excluded.Count, $Output)
