# Workspace Inventory R24

Inventaire non destructif exécuté le 24/08/2026 avec
`tools/workspace_inventory.ps1`.

- `server/` : environ 3 725 MiB, dont environ 3 725 MiB dans `server/target/`.
  Ce cache Rust est déjà ignoré par Git et n'entre pas dans un livrable.
- `client/` : environ 111 MiB.
- `art/` : environ 69 MiB.
- `captures/` : environ 3 MiB et déjà ignoré.
- Quatre dossiers racine anormaux ont été identifiés : `@` et trois noms
  Unicode corrompus. Ils ne sont pas suivis par Git et ne contiennent aucun
  fichier, seulement une arborescence `.thumbnails` vide.

Aucun nettoyage destructif n'est nécessaire pour compiler ou tester. La gate
d'inventaire échoue si l'un des dossiers anormaux acquiert un fichier, afin
d'éviter de supprimer ultérieurement une donnée utilisateur par hypothèse.
