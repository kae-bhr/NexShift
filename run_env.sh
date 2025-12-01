#!/bin/bash
# Script pour lancer Flutter avec un environnement spécifique
# Usage: ./run_env.sh dev
#        ./run_env.sh prod

ENV=${1:-prod}

# Normaliser l'environnement
case "$ENV" in
    development) ENV="dev" ;;
    production) ENV="prod" ;;
esac

echo "🚀 Lancement de l'app en mode $ENV"

# Créer le fichier .env-firebase pour Gradle
echo -n "$ENV" > android/.env-firebase

echo "✅ Fichier .env-firebase créé avec la valeur: $ENV"

# Lancer Flutter avec --dart-define
echo "📱 Lancement de Flutter..."
flutter run --dart-define=ENV=$ENV

# Nettoyer le fichier temporaire
rm -f android/.env-firebase
