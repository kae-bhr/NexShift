# Script pour lancer Flutter avec un environnement specifique
# Usage: .\run_env.ps1 dev
#        .\run_env.ps1 prod

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('dev', 'prod', 'development', 'production')]
    [string]$env = 'prod'
)

# Normaliser l'environnement
$normalizedEnv = switch ($env.ToLower()) {
    'development' { 'dev' }
    'production' { 'prod' }
    default { $env.ToLower() }
}

Write-Host "Lancement de l'app en mode $normalizedEnv" -ForegroundColor Cyan

# Creer le fichier .env-firebase pour Gradle
$envContent = $normalizedEnv
$envFilePath = "android\.env-firebase"
Set-Content -Path $envFilePath -Value $envContent -NoNewline

Write-Host "Fichier .env-firebase cree avec la valeur: $normalizedEnv" -ForegroundColor Green

# Lancer Flutter avec --dart-define
Write-Host "Lancement de Flutter..." -ForegroundColor Cyan
flutter run --dart-define=ENV=$normalizedEnv

# Nettoyer le fichier temporaire
if (Test-Path $envFilePath) {
    Remove-Item -Path $envFilePath -ErrorAction SilentlyContinue
}
