# Script PowerShell pour exécuter les tests avec Firebase Emulator
# Usage: .\test\run_with_emulator.ps1 [test_file]

param(
    [string]$TestFile = "test/integration/replacement/race_condition_test.dart"
)

Write-Host "🚀 Démarrage de Firebase Emulator pour les tests..." -ForegroundColor Green

# Démarrer les émulateurs et exécuter les tests
firebase emulators:exec --only firestore --project nexshift-82473 "flutter test $TestFile"

Write-Host "✅ Tests terminés, émulateur arrêté" -ForegroundColor Green
