# MGU Dashboard

Data field Connect IQ pour montre Garmin qui affiche en direct les données de votre assistance électrique (moteur Pinion MGU) directement sur le poignet.

## Fonctionnalités

- Connexion automatique au vélo via Bluetooth Low Energy (service moteur UUID `0xFD6D`)
- Affichage configurable : puissance cycliste (W), puissance moteur (W), cadence (rpm), mode d'assistance, batterie (%) et autonomie (km)
- Grille d'affichage adaptative (1 à 3 colonnes), chaque métrique activable/désactivable
- **Enregistrement FIT** : puissance, puissance moteur et cadence via les champs natifs Garmin (moyennes, tours, minima visibles dans Garmin Connect), plus assistance, batterie et autonomie
- **Mode démo** : simule un vélo sans BLE pour tester l'affichage
- Libellés multilingues (EN, FR, DE, IT)

## Installation sur la montre

- **Téléphone** : Garmin Connect ▸ Connect IQ Store ▸ rechercher **MGU Dashboard** ▸ Installer
- **Ordinateur** : connect.garmin.com ▸ Connect IQ Store ▸ Installer

Puis ajoutez-le à une activité : **Écrans de données ▸ Ajouter ▸ Connect IQ ▸ MGU Dashboard**.

## Développement

Data field Connect IQ écrit en Monkey C (SDK Garmin Connect IQ).

```
monkeyc -d <device> -f monkey.jungle -o ebikedf.prg -y developer_key.der -w
```

Les images/sorties de build (`bin/`, `*.iq`, `*.prg`, `*.debug.xml`) et les clés de développement (`*.pem`, `*.der`) sont exclues par `.gitignore`.

## Documentation

- [Guide de démarrage rapide — FR](docs/QUICKSTART-FR.md)
- [Quick Start Guide — EN](docs/QUICKSTART-EN.md)
- [Protocole BLE (technique)](docs/PROTOCOL.md)
- [Compilation](docs/BUILD.md)

## Licence

Voir le fichier [LICENSE](LICENSE).