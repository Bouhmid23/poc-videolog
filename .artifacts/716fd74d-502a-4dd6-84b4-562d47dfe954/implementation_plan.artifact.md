# Plan d'amélioration du Scan BLE pour les capteurs Decathlon

L'utilisateur ne voit pas ou ne peut pas connecter ses capteurs Decathlon (HRM et Cadence) dans la boîte de dialogue des capteurs. Ce plan vise à améliorer la classification des appareils, à corriger l'interface utilisateur pour permettre la connexion manuelle et à s'assurer que les appareils déjà découverts sont affichés immédiatement.

## User Review Required

> [!IMPORTANT]
> Nous allons permettre la connexion aux appareils classés comme "Inconnus" en proposant explicitement de les connecter comme "Cardio" ou "Cadence". Cela résoudra le problème des appareils qui n'annoncent pas leurs services Bluetooth standard lors du scan initial.

## Proposed Changes

### [Core] BLE Sensor Service

#### [MODIFY] [ble_sensor_service.dart](file:///D:/Projets/POC OPK/livekitapp/lib/core/ble_sensor_service.dart)
- Ajouter une classification basée sur le nom de l'appareil (ex: contient "HRM", "TILT", "Decathlon").
- Exposer la liste actuelle des appareils découverts via un getter public `discoveredDevices`.
- S'assurer que `startScan` ré-émet la liste actuelle.

### [UI] Sensor Dialog

#### [MODIFY] [controls.dart](file:///D:/Projets/POC OPK/livekitapp/lib/presentation/widgets/controls.dart)
- Initialiser la liste `_devices` dans `initState` avec les appareils déjà connus du service.
- Dans la section "Autres appareils", ajouter des boutons "Connecter HRM" et "Connecter Cadence" pour permettre à l'utilisateur de forcer la connexion si la classification automatique échoue.

## Verification Plan

### Automated Tests
- N/A (Tests manuels requis pour le matériel Bluetooth)

### Manual Verification
- Ouvrir le menu des capteurs sport.
- Vérifier que les appareils déjà allumés apparaissent immédiatement.
- Vérifier que les appareils Decathlon apparaissent dans les sections respectives (HRM/Cadence).
- Si un appareil apparaît dans "Autres appareils", vérifier qu'on peut cliquer sur "Connecter HRM" ou "Connecter Cadence".
- Vérifier la remontée des données en temps réel (BPM/RPM).
