param (
  [Parameter()]
  [switch]
  $UninstallSpotifyStoreEdition = (Read-Host -Prompt 'Désinstaller l édition Spotify du Windows Store si elle existe (O/N)') -eq 'o',
  [Parameter()]
  [switch]
  $UpdateSpotify
)

# Ignorer les erreurs de `Stop-Process`
$PSDefaultParameterValues['Stop-Process:ErrorAction'] = [System.Management.Automation.ActionPreference]::SilentlyContinue

[System.Version] $minimalSupportedSpotifyVersion = '1.2.8.923'

function Get-File {
  param (
    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [System.Uri]
    $Uri,
    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [System.IO.FileInfo]
    $TargetFile,
    [Parameter(ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [Int32]
    $BufferSize = 1,
    [Parameter(ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('KB', 'MB')]
    [String]
    $BufferUnit = 'MB',
    [Parameter(ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('KB', 'MB')]
    [Int32]
    $Timeout = 10000
  )

  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

  $useBitTransfer = $null -ne (Get-Module -Name BitsTransfer -ListAvailable) -and ($PSVersionTable.PSVersion.Major -le 5) -and ((Get-Service -Name BITS).StartType -ne [System.ServiceProcess.ServiceStartMode]::Disabled)

  if ($useBitTransfer) {
    Write-Information -MessageData 'Utilisation d une méthode BitTransfer en mode de secours car vous utilisez Windows PowerShell'
    Start-BitsTransfer -Source $Uri -Destination "$($TargetFile.FullName)"
  } else {
    $request = [System.Net.HttpWebRequest]::Create($Uri)
    $request.set_Timeout($Timeout) # Délai de 15 secondes
    $response = $request.GetResponse()
    $totalLength = [System.Math]::Floor($response.get_ContentLength() / 1024)
    $responseStream = $response.GetResponseStream()
    $targetStream = New-Object -TypeName ([System.IO.FileStream]) -ArgumentList "$($TargetFile.FullName)", Create
    switch ($BufferUnit) {
      'KB' { $BufferSize = $BufferSize * 1024 }
      'MB' { $BufferSize = $BufferSize * 1024 * 1024 }
      Default { $BufferSize = 1024 * 1024 }
    }
    Write-Verbose -Message "Taille du tampon : $BufferSize B ($($BufferSize/("1$BufferUnit")) $BufferUnit)"
    $buffer = New-Object byte[] $BufferSize
    $count = $responseStream.Read($buffer, 0, $buffer.length)
    $downloadedBytes = $count
    $downloadedFileName = $Uri -split '/' | Select-Object -Last 1
    while ($count -gt 0) {
      $targetStream.Write($buffer, 0, $count)
      $count = $responseStream.Read($buffer, 0, $buffer.length)
      $downloadedBytes = $downloadedBytes + $count
      Write-Progress -Activity "Téléchargement du fichier '$downloadedFileName'" -Status "Téléchargé ($([System.Math]::Floor($downloadedBytes/1024))K de $($totalLength)K) : " -PercentComplete ((([System.Math]::Floor($downloadedBytes / 1024)) / $totalLength) * 100)
    }

    Write-Progress -Activity "Téléchargement du fichier '$downloadedFileName' terminé"

    $targetStream.Flush()
    $targetStream.Close()
    $targetStream.Dispose()
    $responseStream.Dispose()
  }
}

function Test-SpotifyVersion {
  param (
    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [System.Version]
    $MinimalSupportedVersion,
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [System.Version]
    $TestedVersion
  )

  process {
    return ($MinimalSupportedVersion.CompareTo($TestedVersion) -le 0)
  }
}

Write-Host @'
**********************************
Auteurs : @ Cassssian eheh *grenouille*
**********************************
'@

$spotifyDirectory = Join-Path -Path $env:APPDATA -ChildPath 'Spotify'
$spotifyExecutable = Join-Path -Path $spotifyDirectory -ChildPath 'Spotify.exe'
$spotifyApps = Join-Path -Path $spotifyDirectory -ChildPath 'Apps'

[System.Version] $actualSpotifyClientVersion = (Get-ChildItem -LiteralPath $spotifyExecutable -ErrorAction:SilentlyContinue).VersionInfo.ProductVersionRaw

Write-Host "Arrêt de Spotify...`n"
Stop-Process -Name Spotify
Stop-Process -Name SpotifyWebHelper

if ($PSVersionTable.PSVersion.Major -ge 7) {
  Import-Module Appx -UseWindowsPowerShell -WarningAction:SilentlyContinue
}

if (Get-AppxPackage -Name SpotifyAB.SpotifyMusic) {
  Write-Host "La version de Spotify du Microsoft Store a été détectée et elle est pas supportée du coup bah cimer frr.`n"

  if ($UninstallSpotifyStoreEdition) {
    Write-Host "Désinstallation de Spotify.`n"
    Get-AppxPackage -Name SpotifyAB.SpotifyMusic | Remove-AppxPackage
  } else {
    Read-Host "Sortie...`nAppuyez sur une touche pour quitter..."
    exit
  }
}

Push-Location -LiteralPath $env:TEMP
try {
  # Nom unique de répertoire basé sur le temps
  New-Item -Type Directory -Name "LeSpot-$(Get-Date -UFormat '%Y-%m-%d_%H-%M-%S')" |
  Convert-Path |
  Set-Location
}
catch {
  Write-Output $_
  Read-Host 'Appuyez sur une touche pour quitter...'
  exit
}

$spotifyInstalled = Test-Path -LiteralPath $spotifyExecutable

if (-not $spotifyInstalled) {
  $unsupportedClientVersion = $true
} else {
  $unsupportedClientVersion = ($actualSpotifyClientVersion | Test-SpotifyVersion -MinimalSupportedVersion $minimalSupportedSpotifyVersion) -eq $false
}

if (-not $UpdateSpotify -and $unsupportedClientVersion) {
  if ((Read-Host -Prompt 'Pour installer Le Spot, votre client Spotify doit étre mis à jour. Voulez-vous continuer ? (O/N)') -ne 'o') {
    exit
  }
}

if (-not $spotifyInstalled -or $UpdateSpotify -or $unsupportedClientVersion) {
  Write-Host 'Téléchargement de la dernière version complète de Spotify, veuillez patienter...'
  $spotifySetupFilePath = Join-Path -Path $PWD -ChildPath 'SpotifyFullSetup.exe'
  try {
    if ([Environment]::Is64BitOperatingSystem) {
      $uri = 'https://download.scdn.co/SpotifyFullSetupX64.exe'
    } else {
      $uri = 'https://download.scdn.co/SpotifyFullSetup.exe'
    }
    Get-File -Uri $uri -TargetFile "$spotifySetupFilePath"
  }
  catch {
    Write-Output $_
    Read-Host 'Appuyez sur une touche pour quitter...'
    exit
  }
  New-Item -Path $spotifyDirectory -ItemType:Directory -Force | Write-Verbose

  [System.Security.Principal.WindowsPrincipal] $principal = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  $isUserAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
  Write-Host 'Exécution de l installation...'
  if ($isUserAdmin) {
    Write-Host
    Write-Host 'Création d une tâche planifiée...'
    $apppath = 'powershell.exe'
    $taskname = 'Installation de Spotify'
    $action = New-ScheduledTaskAction -Execute $apppath -Argument "-NoLogo -NoProfile -Command & `'$spotifySetupFilePath`'"
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -WakeToRun
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskname -Settings $settings -Force | Write-Verbose
    Write-Host 'La tâche d installation a été planifiée. Lancement de la tâche...'
    Start-ScheduledTask -TaskName $taskname
    Start-Sleep -Seconds 2
    Write-Host 'Suppression de la tâche...'
    Unregister-ScheduledTask -TaskName $taskname -Confirm:$false
    Start-Sleep -Seconds 2
  } else {
    Start-Process -FilePath "$spotifySetupFilePath"
  }

  while ($null -eq (Get-Process -Name Spotify -ErrorAction SilentlyContinue)) {
    # Attente de la fin de léinstallation
    Write-Host -NoNewLine '.'
    Start-Sleep -Seconds 2
  }
  Write-Host "`n`nRedémarrage de Spotify..."
  Start-Sleep -Seconds 3
  Start-Process -FilePath $spotifyExecutable
  exit
}
Write-Host 'Spotify est déjà installé. Assurez-vous que votre version est à jour pour utiliser LeSpot.'

# Si la version de Spotify est é jour ou que le client est déjé installé, on continue avec LeSpot
if ($spotifyInstalled -and (-not $UpdateSpotify -and -not $unsupportedClientVersion)) {
  # Fermeture de Spotify avant modification
  Write-Host "Arrêt de Spotify pour appliquer LeSpot..."
  Stop-Process -Name Spotify

  # Vérification et suppression des fichiers de publicité dans le dossier Apps de Spotify
  if (Test-Path -LiteralPath $spotifyApps) {
    Write-Host "Suppression des fichiers de publicité existants dans le dossier Apps..."
    Remove-Item -Path "$spotifyApps\zlink" -Recurse -Force -ErrorAction SilentlyContinue
  }

  # Téléchargement et extraction des fichiers nécessaires pour LeSpot
  Write-Host "Téléchargement des fichiers nécessaires pour LeSpot..."
  $LeSpotUriConfig = 'https://raw.githubusercontent.com/Cassssian/Le-Spot/refs/heads/main/config.ini'
  $configFilePath = Join-Path -Path $spotifyApps -ChildPath 'config.ini'
  $LeSpotUriDpapi = 'https://github.com/Cassssian/Le-Spot/raw/refs/heads/main/dpapi.dll'
  $dpapiFilePath = Join-Path -Path $spotifyApps -ChildPath 'dpapi.dll'

  try {
    Get-File -Uri $LeSpotUriConfig -TargetFile $configFilePath
    Write-Host "Fichier config.ini téléchargé et appliqué avec succès."
    Get-File -Uri $LeSpotUriDpapi -TargetFile $dpapiFilePath
    Write-Host "Fichier dpapi.dll téléchargé et appliqué avec succès."
  }
  catch {
    Write-Host "Erreur lors du téléchargement des fichiers de LeSpot."
    Read-Host 'Appuyez sur une touche pour quitter...'
    exit
  }

  # Redémarrage de Spotify pour prendre en compte les modifications
  Write-Host "Redémarrage de Spotify avec LeSpot activé..."
  Start-Process -FilePath $spotifyExecutable

  Write-Host "LeSpot a été installé avec succés ! Spotify est maintenant lancé avec le blocage des publicités activé."
} else {
  Write-Host "Une erreur est survenue ou Spotify n'est pas installé."
  Read-Host 'Appuyez sur une touche pour quitter...'
}
