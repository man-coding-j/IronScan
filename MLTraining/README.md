# IronScan model training

This pipeline trains an anemia-screening research model from locally stored, provenance-approved tongue images and binary screening labels. It does not establish iron-deficiency anemia and must remain an `engineeringFixture` until independent cohort, parity, calibration, and physical-device validation are complete.

The project owner reported approval to train on and transform the local TongueDX copy on 2026-07-16. Before deploying any resulting model, attach and review its license, consent scope, participant-group mapping, calibration provenance, and laboratory-label definitions in the dataset card.

## Dataset contract

Keep the dataset outside the Git repository. Provide a UTF-8 CSV with these columns:

```csv
image_path,participant_id,anemia_label
images/example-001.jpg,participant-group-001,0
images/example-002.jpg,participant-group-002,1
```

- `image_path` is relative to `--image-root`; absolute paths and path traversal are rejected.
- `participant_id` is used only for participant-grouped splitting. Raw identifiers are never written to reports; split manifests contain salted hashes.
- `anemia_label` must be binary `0` or `1` and follow the dataset's approved anemia-screening labeling protocol.
- Names, email addresses, dates of birth, medical-record identifiers, and private images must never be committed.
- The model consumes calibrated sRGB tongue ROIs. HSV is not an input contract and color-changing augmentation is intentionally excluded.

## Install

Python 3.12 and Xcode are required. Core ML conversion follows Apple's direct PyTorch conversion workflow and uses a Core ML image input.

```bash
cd /path/to/conrad-challenge-ironscan
uv sync --project MLTraining
```

## Train and export

Run from a clean Git worktree so the manifest records the exact training commit:

```bash
uv run --project MLTraining python MLTraining/scripts/train_and_convert.py \
  --metadata-csv /private/path/approved-dataset/metadata.csv \
  --image-root /private/path/approved-dataset \
  --output-directory /private/path/ironscan-artifacts/risk-v0.2.0 \
  --dataset-version approved-dataset-v1 \
  --semantic-version 0.2.0-research.1 \
  --epochs 40 \
  --batch-size 32
```

The script produces `AnemiaRisk.mlpackage`, `risk_manifest.json`, `risk_model_checkpoint.pt`, `evaluation_metrics.json`, and a `split_manifest.json` containing only hashed participant groups.

The validation split fits probability calibration and locks a data-derived decision threshold. The untouched participant-grouped test split reports ROC AUC, balanced accuracy, sensitivity, specificity, and Brier score. A threshold of `0.5` is never assumed.

## Deployment gate

Do not replace the bundled engineering model solely because training completes. Before copying artifacts into `Models/CoreML` and `Models/Manifests`, complete all of the following:

1. Dataset provenance, license, consent, and dataset-card review.
2. Python preprocessing parity fixtures.
3. Swift golden and CPU/all-compute-unit parity tests.
4. Independent participant-grouped evaluation and threshold review.
5. Color-calibration acceptance validation.
6. Physical-device performance and memory testing on at least two iPhones.
7. Human review of the model card, limitations, and deployment status.

The iOS app sends raw preview frames only to segmentation. Risk inference runs only after capture, segmentation, and accepted `CalibratedTongueSample` creation. The UI may display **Possible anemia risk**, **Lower observed risk**, or **Unable to assess**, followed by confirmation guidance for a laboratory test.

Official references: [Apple PyTorch conversion](https://apple.github.io/coremltools/docs-guides/source/convert-pytorch-workflow.html) and [Core ML image inputs](https://apple.github.io/coremltools/docs-guides/source/image-inputs.html).

## TongueDX private review preprocessing

The TongueDX release contains appearance annotations rather than a reviewed hemoglobin or anemia-screening target. They may be used for segmentation, image-quality, coating-stratification, and phenotype research, but the sorter does not rename them as low, moderate, or high anemia risk.

Run the non-destructive private sorter from this repository:

```bash
uv run --project MLTraining python MLTraining/scripts/sort_and_preprocess.py
```

The default root is `~/Documents/IronScanPrivate/TongueDx2`. The script can also run from that directory or accept `--dataset-root`. It creates hashed filenames and a private audit index in `sorted_dataset`, preserves fold memberships, rejects conflicting duplicates and path traversal, and never modifies source files.

The generated groups are:

- `pale_observed`
- `coating_or_toothmark_observed`
- `reference_negative`
- `other_observed`
- `annotation_conflict` for identical image contents with inconsistent annotations

For each image, the optional OpenCV stage uses the supplied tongue segmentation mask, converts BGR pixels to Lab, applies an edge-preserving bilateral filter, applies CLAHE only to the lightness feature, and produces a robust Lab inlier mask. The `a*`-encoded and `b*`-encoded channels are not histogram-equalized. This representation can support research experiments, but it cannot recover tissue color hidden by opaque coating and must not be copied into iOS preprocessing without a new manifest version plus Python/Swift golden parity updates.

Research inference code must call the same reference function rather than reimplementing the transform:

```python
import cv2

from MLTraining.scripts.sort_and_preprocess import extract_lab_features

image_bgr = cv2.imread("/private/path/original.jpg", cv2.IMREAD_COLOR)
tongue_mask = cv2.imread("/private/path/segmentation.jpg", cv2.IMREAD_GRAYSCALE)
features = extract_lab_features(image_bgr, tongue_mask)
model_features = features.lab_features
accepted_pixels = features.valid_tissue_mask
```

This is an experimental feature representation, not the current Core ML input. Before using it on device, define its resize, numeric range, channel order, normalization, and mask handling in a new model manifest and update Python parity fixtures, Swift golden tests, and the model version.

## External prototype tongue fixtures

The local `~/Documents/anemia_detection_eye_nail_tongue-main` repository contains 100 tongue images under each of its `anemia` and `normal` folders. Its own dataset disclosure says the images are augmented prototypes and the hemoglobin labels are simulated proxies. The inspected local copy has no license file and its `labels.csv` is only a Git LFS pointer.

Run a read-only validation and deduplication plan:

```bash
uv run --project MLTraining python MLTraining/scripts/ingest_external_repo.py
```

After a human reviews and records reuse permission, copy the images as engineering fixtures while preserving the external claimed labels:

```bash
uv run --project MLTraining python MLTraining/scripts/ingest_external_repo.py \
  --apply \
  --acknowledge-unvalidated-labels \
  --license-reference "/private/path/to/reviewed-permission-record"
```

The importer reads only `dataset/tongue`, ignores eye and nail directories, verifies JPEG/PNG decoding and copied checksums, avoids content duplicates, and writes collision-safe hashed filenames under `sorted_dataset/external_engineering_fixture/claimed_anemia` and `claimed_normal`. It never moves source files or maps proxy labels to IronScan low, moderate, or high risk decisions.

## Master structural pipeline

Run a read-only sweep of recognized tongue-image sources under `~/Documents`:

```bash
uv run --project MLTraining python -m MLTraining.scripts.master_pipeline
```

The default output is `~/Documents/IronScanMasterDataset`. TongueDX is recognized at either `Documents/IronScanPrivate/TongueDx2` or `Documents/TongueDx2` and is organized into `pallor_present`, `pallor_absent_clean_reference`, `pallor_absent_surface_confounder`, `pallor_absent_other_appearance`, and `annotation_conflict`. The manifest records `TonguePale` as a binary visual-annotation target and excludes conflicts from training eligibility. Coating and tooth-mark strata remain target `0` confounders rather than moderate-risk labels.

The external prototype is organized by its preserved `claimed_anemia` and `claimed_normal` labels. Custom folders containing a `tongue` or `tongues` directory are quarantined as `unreviewed_unlabeled`. Common custom CSV locations are also supported when they contain an `image_path`, `path`, `filepath`, or `file_path` column and the source folder, CSV filename, or referenced relative path explicitly identifies tongue content.

`AIQuest_DATATHON` contains conjunctiva result graphics rather than tongue images, while the inspected `hemoglobin-deficiency-detection` copy contains conjunctiva images, diagrams, and tabular erythema/hemoglobin data without tongue-image links. The scanner reports these repositories as skipped non-tongue media and does not ingest their screenshots or CSV rows.

External and custom sources remain blocked until a reviewed permission record is supplied. The dry-run summary prints the exact source keys. After review, apply with one permission entry per source:

```bash
uv run --project MLTraining python -m MLTraining.scripts.master_pipeline \
  --apply \
  --permission "anemia_detection_github=/private/path/to/reviewed-permission" \
  --permission "external_custom_sources/example=/private/path/to/reviewed-permission"
```

The pipeline copies rather than moves files, verifies every copied checksum, writes `master_manifest.csv` and `master_report.json`, and refuses to overwrite an existing master output. It deliberately does not create low, moderate, or high clinical-risk folders because the available sources do not provide validated laboratory ground truth for those categories. Pallor probability thresholds must be calibrated on a held-out validation cohort and versioned in the model manifest rather than assumed during ingestion.

## Train the visual pallor engineering fixture

The pallor trainer uses the predefined TongueDX fold-1 train/validation files plus `test.csv`, excludes duplicate content that crosses splits or participant groups, and uses the master manifest's binary `TonguePale` target. Class weighting is calculated from the training split only. Random horizontal flipping is enabled; color jitter is intentionally excluded because the target itself is a color annotation.

```bash
uv run --project MLTraining python -m MLTraining.scripts.train_pallor_model \
  --epochs 18 \
  --batch-size 32 \
  --device auto \
  --allow-dirty \
  --replace-existing
```

Artifacts and detailed reports are written under `~/Documents/IronScanPrivate/TrainingArtifacts/pallor-v0.1.0`. After validation, the engineering package is copied to `Models/CoreML/IronScanPallorClassifier.mlpackage` and its contract to `Models/Manifests/pallor_manifest.json`, which places it in the Xcode resource folder. This model does not replace `AnemiaRisk.mlpackage` and must not drive anemia-risk UI decisions.

The locked pallor threshold maximizes validation F1 to make the precision/recall tradeoff explicit. The currently bundled `0.1.1-engineering.1` threshold is `0.162618`; it remains unvalidated for participant use.

## Train the multi-label visual-attribute fixture

`train_multi_label_model.py` predicts `TonguePale`, `Toothmark`, `Crack`, `TipSideRed`, and `FurThick` as source-dataset visual annotations. It uses participant-grouped predefined folds, per-label positive weights, per-label Platt scaling, and per-label validation-locked thresholds. These labels must not be interpreted as diseases, nutrient deficiencies, hydration status, inflammation, or oral-health conditions.

```bash
uv run --project MLTraining python -m MLTraining.scripts.train_multi_label_model --allow-dirty
```

Detailed checkpoints and reports remain private at `~/Documents/IronScanPrivate/TrainingArtifacts/multi-label-v0.1.0`. The training command installs the compiled engineering package at `Models/CoreML/IronScanMultiScreen.mlpackage` and its per-output contract at `Models/Manifests/multi_screen_manifest.json`. The iOS runtime validates and loads the package once, throttles live predictions to one per second, and displays only source-dataset visual-annotation scores against locked thresholds. It does not use these outputs for participant-facing risk decisions. Aggregate evaluation is recorded in `MLTraining/reports/multi-label-v0.1.0/evaluation_summary.json`.
