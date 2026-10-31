# LexOS — PLAY : démarre le LexOS installé sur CETTE clé USB-C dans VirtualBox.
# Lancé par PLAY.exe (déjà en administrateur). Rien n'est installé sur le PC
# à part la machine virtuelle « LexOS-Nomade » (un petit dossier de réglages).
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
function Dire($texte, $icone = 'Information') { [System.Windows.Forms.MessageBox]::Show($texte, 'LexOS', 'OK', $icone) | Out-Null }

# Garder la clé propre : seul PLAY reste visible dans l'Explorateur
$racine = Split-Path $PSScriptRoot -Parent
attrib +h +s "$PSScriptRoot" 2>$null
if (Test-Path "$racine\autorun.inf") { attrib +h +s "$racine\autorun.inf" 2>$null }

$VM  = 'LexOS-Nomade'
$Dir = Join-Path $env:USERPROFILE 'LexOS-Nomade'

# 1. VirtualBox présent ?
$VBox = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'
if (-not (Test-Path $VBox)) {
  $inst = (Get-ItemProperty 'HKLM:\SOFTWARE\Oracle\VirtualBox' -ErrorAction SilentlyContinue).InstallDir
  if ($inst) { $VBox = Join-Path $inst 'VBoxManage.exe' }
}
if (-not (Test-Path $VBox)) {
  Dire "VirtualBox n'est pas installé sur cet ordinateur.`n`nInstalle-le (gratuit), puis clique encore sur PLAY." 'Warning'
  Start-Process 'https://www.virtualbox.org/wiki/Downloads'
  exit 1
}
function vb { & $VBox @args 2>&1 | Out-Null }

# 2. Quelle clé ? Celle où se trouve ce fichier.
$lettre = (Split-Path $PSScriptRoot -Qualifier).TrimEnd(':')
$kit = Get-Partition -DriveLetter $lettre -ErrorAction SilentlyContinue
if (-not $kit) { Dire "Impossible de trouver la clé $lettre`:." 'Error'; exit 1 }
$disque = Get-Disk -Number $kit.DiskNumber
if ($disque.BusType -ne 'USB') { Dire "PLAY doit être lancé depuis la clé USB-C LexOS." 'Error'; exit 1 }
# Toutes les partitions de la clé SAUF celle-ci (Windows l'utilise, LexOS n'en a pas besoin).
$parts = @(Get-Partition -DiskNumber $kit.DiskNumber | Where-Object { $_.PartitionNumber -ne $kit.PartitionNumber } | ForEach-Object { $_.PartitionNumber })
if ($parts.Count -eq 0) { Dire "LexOS n'est pas encore installé sur cette clé." 'Warning'; exit 1 }

# 3. Fermer VirtualBox s'il tourne sans droits admin (sinon : accès refusé à la clé)
Get-Process VirtualBox, VirtualBoxVM, VBoxSVC -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 2

# 4. Créer la machine virtuelle la première fois
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$existe = (& $VBox list vms 2>$null) -match "`"$VM`""
if (-not $existe) {
  vb createvm --name $VM --ostype Debian_64 --register --basefolder $Dir
  vb storagectl $VM --name SATA --add sata --portcount 1 --hostiocache on
} else {
  vb controlvm $VM poweroff
  Start-Sleep 1
  vb discardstate $VM
}
# =============================================================================
#  MOTEUR D'AJUSTEMENT — la meilleure image et la meilleure vitesse pour CE PC
# =============================================================================
#  Alex, 31 octobre : « un moteur qui ajuste automatiquement la VM pour la
#  meilleure qualité d'image et performance de la machine ». Relancé à chaque
#  PLAY : la même clé branchée dans un autre PC se règle pour ce PC-là.
#  Chaque réglage a son propre appel à VBoxManage : un réglage que cette
#  version de VirtualBox ne connaît pas échoue seul, sans emporter les autres.
#  Ce qui a été choisi est écrit dans %USERPROFILE%\LexOS-Nomade\reglages.txt.
$journal = New-Object System.Collections.Generic.List[string]
function Note($t) { $journal.Add($t) }

# --- Ce que l'ordinateur a dans le ventre --------------------------------------
$sys    = Get-CimInstance Win32_ComputerSystem
$ramGo  = [math]::Floor($sys.TotalPhysicalMemory / 1GB)
$fils   = [Environment]::ProcessorCount
$coeurs = (Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfCores -Sum).Sum
if (-not $coeurs) { $coeurs = [math]::Max(1, [math]::Floor($fils / 2)) }
$cartes = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
$gpuDedie = [bool]($cartes -match 'NVIDIA|GeForce|RTX|GTX|Radeon RX|Radeon Pro|AMD Radeon \(TM\) RX|Intel\(R\) Arc')
$ecran  = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$verVB  = (& $VBox --version 2>$null | Select-Object -First 1)
$majeur = 0; if ($verVB -match '^(\d+)\.') { $majeur = [int]$Matches[1] }
#  Hyper-V (ou la sécurité basée sur la virtualisation de Windows 11) prend
#  le processeur pour lui : VirtualBox passe alors en mode lent « NEM ».
$hyperV = $false
try { $hyperV = [bool]((Get-CimInstance Win32_ComputerSystem).HypervisorPresent) } catch {}
Note "PC : $ramGo Go de mémoire, $coeurs coeurs / $fils fils, écran $($ecran.Width) x $($ecran.Height)"
Note "Cartes graphiques : $($cartes -join ' ; ') (dédiée : $gpuDedie)"
Note "VirtualBox $verVB ; Hyper-V actif : $hyperV"

# --- Mémoire : la moitié du PC, entre 3 et 8 Go -------------------------------
#  Au-delà de 8 Go, LexOS nomade ne s'en sert pas : autant la laisser à Windows.
$ram = [math]::Floor($ramGo * 1024 / 2)
$ram = [math]::Max(3072, [math]::Min(8192, $ram))
if ($ramGo -le 6) { $ram = 2048 }

# --- Processeur : les coeurs physiques, moins un pour Windows, de 2 à 8 -------
#  Les « fils » (hyperthreading) comptent moins qu'un vrai coeur dans une VM :
#  donner tous les fils fait ramer Windows ET LexOS.
$cpu = [math]::Max(2, [math]::Min(8, $coeurs - 1))
if ($fils -le 2) { $cpu = 1 }

# --- Image : mémoire vidéo et accélération 3D ---------------------------------
#  Une carte dédiée (NVIDIA, Radeon, Arc) supporte bien la 3D de VMSVGA
#  (VirtualBox 7 et plus) : bureau plus fluide, animations du démon sans
#  saccades. Sur un graphique intégré, la 3D fait souvent plus de mal que de
#  bien : on la laisse fermée. Si la VM refuse de démarrer avec la 3D, on
#  réessaie sans (voir « 6. Démarrer »).
$vram = if ($ramGo -ge 8) { 256 } else { 128 }
$trois_d = ($gpuDedie -and $majeur -ge 7 -and -not $hyperV)

# --- Résolution de départ : celle de l'écran, plafonnée à 1920 x 1080 ---------
#  Sans ça, l'EFI de VirtualBox démarre en 800 x 600 étiré : GRUB et les yeux
#  du démon sont flous. Au-delà de 1080p, une clé USB n'a pas le débit.
$res = '1280x720'
if ($ecran.Width -ge 1366 -and $ecran.Height -ge 768)  { $res = '1366x768' }
if ($ecran.Width -ge 1600 -and $ecran.Height -ge 900)  { $res = '1600x900' }
if ($ecran.Width -ge 1920 -and $ecran.Height -ge 1080) { $res = '1920x1080' }

# --- Appliquer -------------------------------------------------------------------
vb modifyvm $VM --firmware efi --memory $ram --cpus $cpu --graphicscontroller vmsvga --vram $vram --nic1 nat --boot1 disk --boot2 none --mouse usbtablet --usbxhci on
#  Les réglages de vitesse, un par un (noms de VirtualBox 7, puis ceux de 6).
function Regler($nouveau, $ancien) {
  & $VBox modifyvm $VM @nouveau 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0 -and $ancien) { & $VBox modifyvm $VM @ancien 2>&1 | Out-Null }
}
Regler @('--ioapic', 'on') $null
Regler @('--paravirt-provider', 'kvm') @('--paravirtprovider', 'kvm')   # horloge et interruptions natives pour Linux
Regler @('--hwvirtex', 'on') $null
Regler @('--nested-paging', 'on') @('--nestedpaging', 'on')
Regler @('--large-pages', 'on') @('--largepages', 'on')
Regler @('--accelerate-3d', $(if ($trois_d) { 'on' } else { 'off' })) @('--accelerate3d', $(if ($trois_d) { 'on' } else { 'off' }))

vb setextradata $VM 'VBoxInternal2/EfiGraphicsResolution' $res
vb setextradata $VM 'GUI/AutoresizeGuest' 'true'
vb setextradata $VM 'GUI/LastGuestSizeHint' ($res -replace 'x', ',')
#  Pas de mise à l'échelle par VirtualBox : c'est elle qui rend l'image floue
#  sur les écrans à 125 % / 150 %. LexOS reçoit les vrais pixels, et le
#  bureau suit la taille de la fenêtre (lexos-vm-ecran, côté LexOS).
vb setextradata $VM 'GUI/ScaleFactor' '1'
vb setextradata $VM 'GUI/HiDPI/UnscaledOutput' 'true'

Note "Choisi : $ram Mo de mémoire, $cpu processeurs, $vram Mo vidéo, 3D : $trois_d, départ en $res"
if ($hyperV) { Note "Conseil : Hyper-V est actif sur Windows, VirtualBox tourne plus lentement. (Fonctionnalités Windows > décocher Hyper-V / Plateforme de machine virtuelle.)" }
try { $journal | Set-Content -Path (Join-Path $Dir 'reglages.txt') -Encoding UTF8 } catch {}

# 5. Relier la clé (refait à chaque fois : son numéro change selon le port)
$Vmdk = Join-Path $Dir 'cle.vmdk'
vb storageattach $VM --storagectl SATA --port 0 --device 0 --medium none
$uuid = $null
foreach ($l in (& $VBox list hdds 2>$null)) {
  if ($l -match '^UUID:\s+(\S+)') { $uuid = $Matches[1] }
  if ($l -match '^Location:\s+(.+)$' -and $Matches[1].Trim() -ieq $Vmdk) { vb closemedium disk $uuid }
}
if (Test-Path $Vmdk) { Remove-Item $Vmdk -Force -ErrorAction SilentlyContinue }
Get-ChildItem $Dir -Filter 'cle-pt.vmdk' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
$out = & $VBox createmedium disk --filename $Vmdk --format VMDK --variant RawDisk --property "RawDrive=\\.\PhysicalDrive$($kit.DiskNumber)" --property "Partitions=$($parts -join ',')" 2>&1
if (-not (Test-Path $Vmdk)) { Dire "VirtualBox n'a pas pu lire la clé.`nDébranche-la, rebranche-la, puis clique encore sur PLAY.`n`n$($out | Out-String)" 'Error'; exit 1 }
vb storageattach $VM --storagectl SATA --port 0 --device 0 --type hdd --medium $Vmdk

# 6. Démarrer
$out = & $VBox startvm $VM 2>&1
if ($LASTEXITCODE -ne 0 -and $trois_d) {
  #  La 3D est le réglage le plus capricieux (pilote de la carte, version de
  #  VirtualBox) : on la retire et on réessaie avant d'abandonner.
  Regler @('--accelerate-3d', 'off') @('--accelerate3d', 'off')
  Add-Content -Path (Join-Path $Dir 'reglages.txt') -Value 'La 3D a empêché le démarrage : retirée pour ce PC.' -ErrorAction SilentlyContinue
  $out = & $VBox startvm $VM 2>&1
}
if ($LASTEXITCODE -ne 0) { Dire "LexOS n'a pas pu démarrer :`n`n$($out | Out-String)" 'Error'; exit 1 }
