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
$ramGo = [math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
$ram = if ($ramGo -ge 24) { 8192 } elseif ($ramGo -ge 12) { 6144 } else { 4096 }
$cpu = [math]::Max(2, [math]::Min(6, [Environment]::ProcessorCount - 2))
vb modifyvm $VM --firmware efi --memory $ram --cpus $cpu --graphicscontroller vmsvga --vram 128 --nic1 nat --boot1 disk --boot2 none --mouse usbtablet --usbxhci on

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
if ($LASTEXITCODE -ne 0) { Dire "LexOS n'a pas pu démarrer :`n`n$($out | Out-String)" 'Error'; exit 1 }
