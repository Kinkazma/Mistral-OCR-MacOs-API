# MistralOCR

## Niveau de difficulté
**Installation sans code** : une personne qui ne sait pas programmer mais sait suivre des étapes peut installer et utiliser l’application. Aucune dépendance externe, aucun outil CLI, aucun XcodeGen requis (le projet **.xcodeproj** est fourni et prêt).

## 1) Description fonctionnelle

### 1.1 Fenêtre principale
- **Zone de dépôt (glisser-déposer)** : déposez des fichiers (images, PDF, etc.) et dossiers.  
  - Si **Auto-envoi** est activé, l’OCR démarre immédiatement et :
    - le **texte** est exporté dans le **dossier d’export**,
    - le **résultat** est ajouté à l’**Historique**,
    - le **texte OCR** est copié dans le **presse-papiers** pour usage immédiat (permettant d'utiliser une application de presse papier comme historique combiné).
  - Sinon, les éléments s’ajoutent à la **file d’attente** du **Panneau d’envoi** (SendPanel) et vous déclenchez l’OCR quand vous voulez.

- **Panneau d’envoi** :
  - **Modèle** OCR Mistral sélectionnable.
  - **Format de sortie** :  
    - `Markdown`,  
    - `Markdown (sans images)`,  
    - `JSON (Annotations)`.
  - **Inclure les images** (images encodées en base64 dans la réponse, si activé).
  - **Préserver l’arborescence** (envoi manuel) : si vous traitez plusieurs éléments, l’export peut **recréer la structure de dossiers** relative sous le dossier d’export.

### 1.2 Historique (sélection multi, copie, suppression)
- Chaque OCR produit un **Item d’historique** (titre = nom de fichier source, texte OCR, chemin du fichier exporté).
- **Clic simple** : sélection simple et mise à jour de l’ancre.
- **⇧ + clic (JUST MAJ)** : sélection par plage contiguë. (A+B+C+D+…N)
- **⌥ + ⇧ + clic (ALT + MAJ)** : ajout/suppression ponctuelle dans une sélection (toggle) sans modifier l’ancre. (B+E+U+R+…N)
- **Clic droit** Pemret d'accéder à plus de fonctions comme copier le fichier, ou l'OCR ou voir dans le Finder.
- **Actions** :  
  - **Copier** le texte OCR combiné,  
  - **Supprimer** le ou les items d’historique choisis.
  - **Tout Copier** …
  - **Tout Supprimer** …

### 1.3 Icône barre de menus
- Icône en couleur en barre de menus.
- Menu rapide : **Afficher la fenêtre**, **Mini Historique**, **Quitter**.

### 1.4 Raccourci clavier global
- Par défaut **⌘⇧O**.
- **Entièrement configurable** dans **Préférences**.
- Persisté et re-enregistré immédiatement en faisant un nouveau raccourci clavier après avoir ouvert les préférences.

### 1.5 Dossier de versement automatique (watcher)
- Scanne un dossier toutes les 5 secondes et traite tout nouveau fichier.
- **Export** dans un dossier d’export dédié au watcher.
- **Gestion des originaux** : Corbeille système ou dossier corbeille dédié (sans suppression automatique).
- Ignore ses propres dossiers d’export/corbeille.
- **NE PAS CHANGER LEUR NOM SANS LES CHANGER AUSSI DANS L'APPLICATION**

### 1.6 Extension de partage
- Partage depuis d’autres apps vers **MistralOCR**.

### 1.7 Stockage local & journaux
- Historique : `~/Library/Application Support/MistralOCR_Desktop/history.json`.
- Paramètres : UserDefaults.
- Journaux exportables.

## 2) Préférences
- **MISTRAL_API_KEY** avec test.
- **Modèle**.
- **Inclure les images**.
- **Dossier d’export**.
- **Auto-envoi**.
- **Préserver l’arborescence**.
- **Raccourci global**.
- **Watcher** et options associées.

## 3) Procédure d’installation
### Prérequis
- **macOS 14.0**+
- **Xcode** (Mac App Store)

### Étapes
1. Décompresser l’archive.
2. Ouvrir `MistralOCR_Desktop.xcodeproj`.
3. Configurer **Signing & Capabilities**.
4. Sélectionner le schéma `MistralOCR_Desktop` et **Run**.
5. Configurer les préférences.
6. (Optionnel) **Archiver** pour distribuer.

## 4) Dépannage rapide
- **Raccourci global** : changer si conflit.
- **Pas d’export** : vérifier API key et modèle.
- **Watcher inactif** : reconfigurer le dossier.
- **Auto-envoi** : copie directe au presse-papiers.

## 5) Sécurité
- **Clé API stockée en clair dans UserDefaults.**
- Pas de serveur tiers, tout est local sauf l’API Mistral.
- Je n'ai 'évidemment' aucune emprise sur la politique de confidentialité de Mistral.
