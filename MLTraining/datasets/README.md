# Dataset boundary

Private datasets must remain outside the repository. Only reviewed dataset cards and participant-grouped split manifests may be committed here. Never commit names, participant identifiers, dates of birth, laboratory reports, or real participant images.

The project owner reported approval to train on and transform the locally supplied TongueDX copy on 2026-07-16. Supporting license, consent scope, participant-group mapping, calibration provenance, and laboratory-label definitions must still be captured in a reviewed dataset card before model deployment.

The expected training metadata contract is documented in `MLTraining/README.md`. Split manifests must contain anonymized participant-group hashes only. Hemoglobin-only labels may support an anemia-screening model but do not independently establish iron-deficiency anemia.

The local `anemia_detection_eye_nail_tongue-main` repository states that its images are augmented prototype data and its hemoglobin values are proxy/simulated labels. No license file was present in the inspected local copy on 2026-07-20. These files may not be represented as IronScan low/high risk data and must remain excluded from deployable model training and validation unless provenance, reuse permission, participant grouping, and laboratory ground truth are independently established.
