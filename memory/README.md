# memory/ — fichiers de reprise rapide

Ces fichiers condensés permettent à un agent (ou à l'utilisateur) de reprendre le
projet après un reset de contexte **sans relire tout l'historique**.

| Fichier | Rôle |
|---|---|
| `GDD.md` | Règles du jeu (condensé de `docs/GDD.md` qui reste la source de vérité complète) |
| `ARCHITECTURE.md` | Stack, contrat d'API exact, config, anti-triche |
| `DECISIONS.md` | Décisions structurantes (utilisateur + techniques) — ne pas rouvrir sans demande |
| `CURRENT_STATE.md` | Où on en est, ce qui est vérifié, ce qui ne l'est pas, acceptance |
| `TODO.md` | Prochaines tâches par milestone, checklist |

> **Swap d'agent** : `.cursor/rules/cyberseeker.mdc` (racine du repo) = point d'entrée auto-chargé par Cursor (protocole de reprise + règles dures + état). En cas de divergence, ces fichiers mémoire gagnent ; le `.mdc` est mis à jour en même temps que `CURRENT_STATE.md`.

## Règle de maintenance (obligatoire)
1. **À chaque changement significatif** (endpoint modifié, décision prise, milestone terminé, bug d'architecture) : mettre à jour le(s) fichier(s) mémoire concerné(s) dans la même session.
2. Rester **condensé** : si un fichier dépasse ~60 lignes, résumer davantage ou pointer vers le doc complet (`docs/`).
3. En cas de conflit entre `memory/` et `docs/` : **`docs/` gagne** (source de vérité) — puis corriger `memory/`.
4. Le code serveur (`server/src/*.rs`) est le contrat d'API définitif, pas ce fichier.
5. Ne jamais stocker ici de secrets (clés, adresses de trésorerie réelles, etc.).
