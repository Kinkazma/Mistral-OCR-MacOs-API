# MistralOCR_Desktop

Projet macOS (SwiftUI + AppKit) avec barre de menus, Services, Share Extension, historique, conversion automatique des formats et client Mistral OCR.

## Build rapide

Ouvrir `MistralOCR_Desktop.xcodeproj` dans Xcode, `⌘B`, puis `⌘R`, si tout fonctionne allez dans : 'Product' puis 'Archive'
Cliquez sur 'Distribute App' ; 'Custom' ; 'Copy App' ; Enregistrez-la ; Déplacez là dans dossier 'Applications'
'Enjoy'

## Configuration

- Ajoutez votre clé dans Préférences (MISTRAL_API_KEY).
- Modèle par défaut : `mistral-ocr-latest`. Vous pouvez rafraîchir et choisir une version figée.
- Services : `Mistral OCR : Copier` apparaît dans le menu Services au clic droit.
- Share Extension : “MistralOCR Share” dans le menu Partager (envoie l’URL à l’app via `mistralocr://`).
- Raccourci global : à compléter (exemple à brancher via EventTap/Carbon si souhaité).
- Logs : `~/Library/Logs/MistralOCR_Desktop/` et export via menu Aide (à ajouter).

## Notes

- Conversion : images non listées (HEIC/JP2/TIFF, etc.) → PNG. Autres formats → PDF.
- Limites Mistral : 50 MB, 1000 pages.
