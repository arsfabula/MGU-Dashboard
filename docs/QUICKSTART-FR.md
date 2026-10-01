# MGU Dashboard — Guide de démarrage rapide

Data field Connect IQ pour montre Garmin qui affiche en direct sur le poignet les données de votre assistance électrique (moteur Pinion MGU).

## 1. Description
Ajouté à un écran de données d'une activité, il se connecte automatiquement au vélo par Bluetooth Low Energy. L'écran est organisé en bandes fixes : **jauge radiale de puissance cycliste** (arc épais épousant le haut de l'écran, de 10 h à 14 h, échelle 0→2×FTP avec 7 segments de couleur et aiguille), bande **Moteur / Cadence / Assistance**, bande **Batterie / Autonomie**, et nom du vélo en pied d'écran. Chaque métrique des bandes se règle dans le menu (§4), la puissance étant toujours affichée par la jauge.

L'échelle de la jauge va de 0 à **2×FTP** : l'aiguille est au zénith quand vous pédalez à votre FTP, et la zone centrale (jaune) correspond à FTP ±15 %. Les 7 segments ont tous la même largeur et se lisent, de gauche à droite, du gris (très facile) au violet (très au-dessus du FTP), en passant par le bleu, le vert et le jaune ; les faibles puissances sont donc à gauche, les fortes à droite. Le FTP est choisi dans le menu (§4) ; à « **Auto** », le champ utilise le FTP de votre profil utilisateur s'il est disponible, sinon 200 W.

En plus de l'écran :
- **Enregistrement FIT** : puissance, puissance moteur, cadence, assistance, batterie et autonomie sont enregistrées dans l'activité ; puissance, puissance moteur et cadence utilisent les champs natifs Garmin (moyennes, tours, minima dans Garmin Connect).
- **Mode démo** : simule un vélo sans BLE pour tester l'affichage.

## 2. Installation du data field
**Depuis le téléphone (recommandé)** : dans Garmin Connect, ouvrez **Connect IQ Store**, recherchez **MGU Dashboard**, touchez **Installer** et choisissez votre montre.
**Depuis un ordinateur** : connect.garmin.com ▸ Connect IQ Store ▸ Installer.

Prérequis : montre compatible Connect IQ, Garmin Connect Mobile installé et montre synchronisée.

### Ajouter à une activité
- **Sur la montre** : démarrez une activité (ex. Vélo), bouton central maintenu ▸ **Écrans de données** ▸ **Ajouter** ▸ **Connect IQ** ▸ MGU Dashboard.
- **Depuis le téléphone** : Garmin Connect ▸ **Plus** ▸ **Profils d'activité** ▸ activité ▸ **Écrans de données** ▸ **Ajouter** ▸ Connect IQ ▸ MGU Dashboard.

## 3. Connexion automatique
Aucune configuration : tout est automatique. Le champ scanne les équipements BLE annonçant le service du moteur (UUID `0xFD6D`) et affiche « Recherche… ». Au premier jumelage, confirmez l'appairage. Une fois connecté, les données arrivent en continu (~1,3 s) ; le nom du vélo apparaît en titre. Un heartbeat maintient la liaison.

États d'écran : « Recherche… » (scan en cours), « En attente… » (connecté, pas de données depuis ~10 s), `--` (donnée indisponible). En cas de perte de connexion, le scan repart automatiquement.

## 4. Fonctionnalités & menu
Menu : Activité ▸ **Réglages de l'activité** ▸ **Champs Connect IQ** ▸ **MGU Dashboard**.

Options :
- **Mode démo** : données simulées sans vélo ni BLE (écran « Démo »).
- **Libellés** : nom de chaque métrique (défaut : activé).
- **Moteur / Cadence / Assistance / Batterie / Autonomie** : active/désactive chaque métrique des bandes (défaut : toutes activées). La jauge de puissance est toujours affichée.
- **FTP** : seau de valeurs **Auto** (défaut) ou 60–400 W par pas de 5 W. Utilisé pour l'échelle de la jauge (voir §1).
- **Debug (mesures)** : journal d'agencement des bandes, pour diagnostic.

Enregistrement : continu (puissance, cadence, assistance, batterie, autonomie), résumé (puissance moyenne, cadence moyenne, batterie mini) et par tour (moyennes) — visibles dans Garmin Connect. L'enregistrement est piloté par les callbacks BLE : il continue même si une autre page de données est affichée (seul le mode démo nécessite le champ visible).

## 5. Notes & limites
Données reçues environ toutes les 1,3 s (flux natif du moteur, pas au rythme du GPS). Seule la liaison BLE consomme la batterie de la montre. Le mode démo coupe la connexion au vélo jusqu'à sa désactivation.

## 6. Dépannage rapide
- « Recherche… » en continu : vélo éteint ou trop loin → rapprochez-vous, moteur allumé, écran réveillé.
- « En attente… » : relancez l'activité ou coupez/remettez le moteur.
- Pas d'appairage : le vélo est déjà appairé ; sinon oubliez-le dans les réglages Bluetooth de la montre.
- Jauge illisible (aiguille toujours au maximum) : le FTP « Auto » est trop bas (profil) → choisissez une valeur dans le menu §4.
- Écran blanc **dans le simulateur** : activez **Mode démo** (le simulateur n'implémente pas le Bluetooth, l'application ne peut pas démarrer si le démo est désactivé).
- Test sans vélo : activez **Mode démo**, puis désactivez-le.

*Technique : docs/PROTOCOL.md (protocole BLE), docs/BUILD.md (compilation).*