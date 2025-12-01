#!/bin/bash
# Script pour exécuter les tests avec Firebase Emulator
# Usage: ./test/run_with_emulator.sh [test_file]

set -e

echo "🚀 Démarrage de Firebase Emulator pour les tests..."

# Démarrer les émulateurs et exécuter les tests
firebase emulators:exec \
  --only firestore \
  --project nexshift-82473 \
  "flutter test ${1:-test/integration/replacement/race_condition_test.dart}"

echo "✅ Tests terminés, émulateur arrêté"
