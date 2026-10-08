#!/usr/bin/env bash
# Installe Ascender (et le K3s qui le porte) sur la machine courante.
#
# Lancé automatiquement au premier démarrage de l'instance (cloud-init, voir terraform/outils),
# ou à la main :  sudo bash /opt/plateforme/installer-ascender.sh
#
# - Idempotent : relancé après une installation réussie, il ne fait rien (FORCER=1 pour réinstaller).
# - Le mot de passe admin est généré ICI et stocké dans /root/ascender-admin-password :
#   il ne passe ni par Git, ni par Terraform, ni par les métadonnées EC2.
# - Journal complet : /var/log/installation-ascender.log
set -euo pipefail

VERSION_INSTALLATEUR="${VERSION_INSTALLATEUR:-25.6.2}"
DOSSIER_CONFIG="$(cd "$(dirname "$0")" && pwd)"
CONFIG_SOURCE="${DOSSIER_CONFIG}/custom.config.yml"
INSTALLATEUR=/opt/ascender-install
FICHIER_MDP=/root/ascender-admin-password
TEMOIN=/var/lib/plateforme/ascender-installe
JOURNAL=/var/log/installation-ascender.log

exec > >(tee -a "$JOURNAL") 2>&1
echo "=== $(date -Is) : installation d'Ascender ${VERSION_INSTALLATEUR} ==="

if [ "$(id -u)" -ne 0 ]; then
  echo "Ce script doit être lancé avec sudo."
  exit 1
fi

if [ -f "$TEMOIN" ] && [ "${FORCER:-0}" != "1" ]; then
  echo "Ascender est déjà installé ($(cat "$TEMOIN")). Rien à faire (FORCER=1 pour réinstaller)."
  exit 0
fi

[ -f "$CONFIG_SOURCE" ] || { echo "Configuration introuvable : $CONFIG_SOURCE"; exit 1; }

echo "--- Paquets nécessaires"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q git openssl

echo "--- Installateur officiel, version épinglée ${VERSION_INSTALLATEUR}"
if [ ! -d "$INSTALLATEUR/.git" ]; then
  git clone --quiet --depth 1 --branch "$VERSION_INSTALLATEUR" \
    https://github.com/ctrliq/ascender-install.git "$INSTALLATEUR"
fi

echo "--- Mot de passe administrateur"
if [ ! -s "$FICHIER_MDP" ]; then
  openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24 > "$FICHIER_MDP"
  chmod 600 "$FICHIER_MDP"
  echo "Généré dans $FICHIER_MDP"
fi

echo "--- Configuration"
# Supprime d'éventuelles fins de ligne Windows (fichier passé par un poste Windows)
sed 's/\r$//' "$CONFIG_SOURCE" > "$INSTALLATEUR/custom.config.yml"
sed -i "s|__MOT_DE_PASSE__|$(cat "$FICHIER_MDP")|" "$INSTALLATEUR/custom.config.yml"
chmod 600 "$INSTALLATEUR/custom.config.yml"

echo "--- Installation (10 à 20 minutes)"
cd "$INSTALLATEUR"
./setup.sh

mkdir -p "$(dirname "$TEMOIN")"
echo "version ${VERSION_INSTALLATEUR}, le $(date -Is)" > "$TEMOIN"

echo
echo "=== Ascender est installé ==="
echo "Utilisateur : admin"
echo "Mot de passe : sudo cat $FICHIER_MDP"
echo "Accès : voir README, section « Accéder à Ascender »"
