# CYBERSEEKER — CHECKLIST RELEASE ANDROID / SEEKER

## Automatisable localement

- [x] `cargo test` et validation de la remote config.
- [x] Migrations PostgreSQL appliquées sur la base locale.
- [x] Smoke test des six écrans Godot.
- [x] Preset Android arm64, API min 24 / cible 36 (template Godot 4.7.2).
- [x] Icône originale et assets mobiles importables.
- [x] Mode dev refusé par un serveur Rust release.
- [x] Paiement/pub sans preuve refusés hors mode dev.
- [x] Installer JDK 17, SDK Android, Platform/Build Tools 35 et 36.
- [x] Installer les templates Android officiels Godot 4.7.2 après contrôle SHA-512.
- [x] Générer `client/build/android/CyberSeeker-debug.apk`.
- [x] Vérifier la signature APK v2/v3 avec `apksigner`.

## Validation nécessitant un appareil ou un compte externe

- [ ] Générer/sauvegarder le keystore release appartenant au compte éditeur,
      puis produire l'AAB/APK de publication.
- [ ] Remplacer `Wallet.gd` release par le bridge Solana Mobile Wallet Adapter.
- [ ] Signer le nonce réel et valider adresse/signature Ed25519 sur Seeker.
- [ ] Raccorder un provider de publicité récompensée avec reçu signé côté serveur.
- [ ] Raccorder un RPC/indexeur Solana et vérifier mint, montant, destinataire,
      finalité et signature avant de créditer une offre.
- [ ] Tester vibration, rotation verrouillée, reprise arrière-plan et réseau mobile.
- [ ] Mesurer mémoire, température, batterie et stabilité sur au moins 30 minutes.
- [ ] Fournir URL HTTPS d'API, politique de confidentialité et support.
- [ ] Créer fiche dApp Store, captures, classification d'âge et formulaire données.
- [ ] Valider conformité SKR, publicité et achats dans les pays ciblés.

Ces cases ne peuvent pas être certifiées par un environnement local sans appareil,
identifiants de publication, réseau de publicité et infrastructure Solana choisie.
