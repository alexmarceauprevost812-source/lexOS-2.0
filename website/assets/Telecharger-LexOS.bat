@echo off
rem ===========================================================================
rem  LexOS — telecharger l'ISO EN UN SEUL FICHIER, d'un double-clic (Windows)
rem ===========================================================================
rem  GitHub refuse les fichiers de plus de 2 Go : l'ISO y est en morceaux.
rem  Ce petit programme les telecharge, les recolle, verifie l'empreinte
rem  SHA-256 et laisse UNE seule ISO dans ton dossier Telechargements.
rem  Il ne parle qu'a github.com (le depot public de LexOS) et n'installe rien.
rem ===========================================================================
title LexOS - telechargement de l'ISO
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t = Get-Content -Raw -LiteralPath '%~f0'; iex ($t -split ('#'+'PS'+'#'), 2)[1]"
echo.
pause
exit /b
#PS#
$ErrorActionPreference = 'Stop'
$depot = 'alexmarceauprevost812-source/lexOS-2.0'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host ''
Write-Host '  LexOS - telecharger l''ISO en un seul fichier' -ForegroundColor DarkYellow
Write-Host ''
Write-Host '   1) LexOS Pro     - installe sur ton PC (pilote NVIDIA compris)'
Write-Host '   2) LexOS Nomade  - sur une cle USB-C (VirtualBox via PLAY)'
Write-Host ''
$choix = Read-Host '  Ton choix (1 ou 2)'
$saveur = if ($choix -eq '2') { 'nomade' } else { 'pro' }

$rel = Invoke-RestMethod "https://api.github.com/repos/$depot/releases/tags/latest-$saveur" -Headers @{ 'User-Agent' = 'LexOS' }
$morceaux = @($rel.assets | Where-Object { $_.name -like '*.iso.part-*' } | Sort-Object name)
$empreinte = $rel.assets | Where-Object { $_.name -like '*.iso.sha256' } | Select-Object -First 1
if ($morceaux.Count -eq 0) { throw "Aucun morceau d'ISO trouve dans la Release latest-$saveur." }
$nom = $morceaux[0].name -replace '\.part-\d+$', ''
$dossier = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
$iso = Join-Path $dossier $nom
$total = ($morceaux | Measure-Object -Property size -Sum).Sum
$libre = (Get-PSDrive ($dossier.Substring(0,1))).Free
if ($libre -lt ($total * 2)) { throw ("Pas assez de place dans {0} : il faut {1:N1} Go libres." -f $dossier, ($total * 2 / 1GB)) }

Write-Host ''
Write-Host ("  {0} - {1} morceaux, {2:N1} Go au total" -f $nom, $morceaux.Count, ($total / 1GB))
Write-Host "  Destination : $iso"
Write-Host ''

$parts = @()
foreach ($m in $morceaux) {
  $cible = Join-Path $dossier $m.name
  if ((Test-Path $cible) -and ((Get-Item $cible).Length -eq $m.size)) {
    Write-Host "  - $($m.name) : deja la, on le garde"
  } else {
    Write-Host "  - $($m.name) : telechargement..."
    # curl.exe est livre avec Windows 10 et 11 : barre de progression et reprise (-C -)
    & curl.exe -L --fail --retry 5 -C - -o $cible $m.browser_download_url
    if ($LASTEXITCODE -ne 0) { throw "Le telechargement de $($m.name) a echoue. Relance ce fichier : il reprendra ou il s'est arrete." }
  }
  $parts += $cible
}

Write-Host ''
Write-Host '  Recollage des morceaux en une seule ISO...'
$sortie = [IO.File]::Create($iso)
try {
  foreach ($p in $parts) {
    $entree = [IO.File]::OpenRead($p)
    try { $entree.CopyTo($sortie, 8MB) } finally { $entree.Close() }
  }
} finally { $sortie.Close() }

if ($empreinte) {
  Write-Host '  Verification de l''empreinte SHA-256...'
  $brut = (Invoke-WebRequest $empreinte.browser_download_url -UseBasicParsing -Headers @{ 'User-Agent' = 'LexOS' }).Content
  if ($brut -is [byte[]]) { $brut = [Text.Encoding]::ASCII.GetString($brut) }
  $attendu = ($brut.Trim() -split '\s+')[0].ToLower()
  $obtenu = (Get-FileHash $iso -Algorithm SHA256).Hash.ToLower()
  if ($attendu -and $obtenu -ne $attendu) {
    Remove-Item $iso -Force
    throw "L'empreinte ne correspond pas : un morceau est abime. Supprime les fichiers .part de $dossier et relance."
  }
  Write-Host '  Empreinte OK : le fichier est intact.' -ForegroundColor Green
}

$parts | ForEach-Object { Remove-Item $_ -Force -ErrorAction SilentlyContinue }
Write-Host ''
Write-Host "  C'est pret : $iso" -ForegroundColor Green
Write-Host '  Grave-la sur une cle USB avec balenaEtcher, puis demarre dessus (F12).'
Start-Process explorer.exe "/select,`"$iso`""
