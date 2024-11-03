# Le Spot
 c'est le spot


bah tu dois juste exécuter la commande là dans un powershell : 

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-Expression "& { $(Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/Cassssian/Le-Spot/master/install.ps1') } -UninstallSpotifyStoreEdition -UpdateSpotify"
```

et c bon voilà mdr !!