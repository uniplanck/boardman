# Board-Man

[English](../../README.md) / [ja](README.ja.md) / [zh-CN](README.zh-CN.md) / [es](README.es.md) / [pt-BR](README.pt-BR.md) / [ko](README.ko.md) / [de](README.de.md) / [fr](README.fr.md)

Board-Man est une app de productivité pour le presse-papiers macOS dérivée de Clipy.

Elle garde l'historique du presse-papiers accessible depuis la barre de menus et ajoute une visibilité orientée flux de travail pour les personnes qui copient, collent, modifient et déplacent régulièrement du texte, des URL, des commandes et des images entre plusieurs apps.

> Statut : candidat public. Ce dépôt est une édition open source assainie, préparée à partir d'une build privée en développement actif.

## Capture d'écran

![Board-Man main screenshot](../assets/board-man-main-screenshot.png)

## Ce que Board-Man peut faire

- Garder l'historique récent du presse-papiers accessible depuis la barre de menus.
- Enregistrer et coller des snippets réutilisables.
- Afficher des badges de nombre de collages pour les éléments souvent utilisés.
- Gérer les entrées d'image du presse-papiers, y compris le contenu uniquement composé d'une image, comme une capture d'écran.
- Rechercher dans l'historique du presse-papiers.
- Naviguer dans le panneau au clavier.
- Épingler les éléments importants.
- Ajuster les raccourcis, les limites d'historique, le comportement du menu et les options de thème visuel.
- Fonctionner localement sur macOS sans envoyer le contenu du presse-papiers à un service externe.

## Téléchargement

- [Télécharger Board-Man v1.2.3](https://github.com/uniplanck/boardman/releases/tag/v1.2.3)
- Archive de l'app macOS : `Board-Man-v1.2.3.zip`

## Installation et premier lancement

1. Téléchargez `Board-Man-v1.2.3.zip` depuis la page de release.
2. Décompressez l'archive.
3. Déplacez `Board-Man.app` vers `/Applications`.
4. Ouvrez Board-Man.

Si macOS Gatekeeper bloque le premier lancement, ouvrez **System Settings > Privacy & Security** et autorisez Board-Man, ou faites Control-click sur l'app et choisissez **Open**.

## Utilisation de base

1. Copiez du texte, une URL, une commande ou une image comme d'habitude.
2. Ouvrez Board-Man depuis la barre de menus.
3. Recherchez ou parcourez l'historique du presse-papiers.
4. Sélectionnez un élément pour le coller dans l'app active.
5. Utilisez les snippets pour le texte que vous collez souvent.

## Historique du presse-papiers

Board-Man stocke les éléments récents du presse-papiers afin que vous puissiez revenir à du texte, des URL, des commandes et des entrées d'image sans les copier de nouveau.

Utilisez-le lorsque vous voulez :

- réutiliser quelque chose copié plus tôt
- éviter de passer d'un document à l'autre uniquement pour recopier le même texte
- garder des commandes ou URL récentes à portée de main
- revoir le déroulé d'un travail intensif en copier-coller

## Snippets

Les snippets sont des entrées de texte réutilisables pour les phrases, modèles, URL, commandes et autres contenus que vous collez souvent.

Usages typiques :

- réponses répétées
- modèles de commandes
- blocs de texte marketing ou pour les réseaux sociaux
- messages de support
- URL et courts textes standard

## Badges de nombre de collages

Les badges de nombre de collages indiquent combien de fois un élément a été collé.

Cela vous aide à repérer :

- le texte que vous réutilisez souvent
- les commandes que vous exécutez régulièrement
- les ressources ou snippets centraux dans votre flux de travail
- les schémas de copier-coller qui pourraient mériter de devenir des snippets ou des automatisations

## Prise en charge des images du presse-papiers

Board-Man prend en charge les entrées d'image du presse-papiers et peut afficher le contenu uniquement composé d'une image dans la liste de l'historique.

C'est utile lors de la copie de :

- captures d'écran
- graphiques
- références de design
- contenu visuel du presse-papiers entre apps

Les entrées d'image utilisent une identité basée sur l'horodatage afin que les noms génériques comme `TIFF image` ou `PNG image` n'entrent pas en collision dans les compteurs de collage.

## Recherche et navigation au clavier

Utilisez la recherche pour filtrer l'historique du presse-papiers. Le panneau est conçu pour une utilisation au clavier afin de rechercher, parcourir les résultats et coller sans quitter le flux de travail en cours.

## Réglages et apparence

Board-Man inclut des réglages pour le comportement du menu, les raccourcis, les limites d'historique et l'apparence visuelle. Selon la build actuelle, vous pouvez utiliser des options de thème et d'affichage plus clair pour rendre le panneau plus lisible.

## Confidentialité

Board-Man est un utilitaire macOS local. Le contenu du presse-papiers est traité localement par l'app. Ne stockez pas de secrets, tokens, mots de passe ou données privées de clients dans l'historique du presse-papiers sauf si vous comprenez le risque.

## Licence et attribution

Board-Man est une oeuvre dérivée fortement modifiée basée sur Clipy.

Ce dépôt conserve l'attribution et les avis de licence du projet amont :

- `ATTRIBUTION.md`
- `LICENSE`
- `LICENSE_CLIPMENU`

Board-Man est distribué sous les conditions de la licence MIT héritées de Clipy. Il n'est pas approuvé par les mainteneurs amont de Clipy ou ClipMenu.
