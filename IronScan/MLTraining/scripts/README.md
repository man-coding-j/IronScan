# Training scripts

Reserved for deterministic data validation, training, export, and evaluation entry points.

`train_and_convert.py` trains the participant-grouped binary risk model, fits validation probability calibration, locks a decision threshold, exports `AnemiaRisk.mlpackage`, and writes its model manifest and evaluation artifacts. See `MLTraining/README.md` for the data contract and commands.

`sort_and_preprocess.py` reads the private TongueDX fold CSVs, resolves only the original and segmentation images, de-duplicates overlapping fold paths and image contents, quarantines conflicting content annotations, and writes a private review set under `TongueDx2/sorted_dataset`. It deliberately uses appearance phenotype folders rather than anemia-risk folders because `TonguePale`, coating, redness, and tooth-mark annotations are not laboratory anemia labels.

`ingest_external_repo.py` validates tongue-only images from the local `anemia_detection_eye_nail_tongue-main` prototype repository. It ignores eye and nail folders, performs a dry run by default, verifies JPEG/PNG decoding and checksums, and can copy reviewed files into `external_engineering_fixture/claimed_*`. The source disclosure identifies its labels as simulated proxies, so the script refuses to map them into IronScan risk folders and requires both explicit acknowledgement and a reviewed license or permission reference before `--apply`.

`master_pipeline.py` is the source-separated Documents ingestion entrypoint. It recognizes TongueDX, either local name of the eye/nail/tongue prototype repository, and custom top-level folders containing a directory named `tongue` or `tongues`. It performs a dry run by default, blocks external/custom files without a recorded `--permission`, copies atomically on `--apply`, and writes checksummed provenance manifests. It preserves neutral appearance, claimed proxy, or unreviewed labels and never creates low/moderate/high risk folders from unvalidated data.

`train_pallor_model.py` trains a MobileNetV3-Small engineering fixture against the visual `TonguePale` annotation using the predefined TongueDX fold-1 train/validation split and untouched test CSV. It excludes cross-split duplicate content and ambiguous participant assignments, computes class weight from the training split only, logs validation ROC-AUC/precision/recall/F1, fits validation-only Platt calibration, locks a validation-derived threshold, reports test metrics and a confusion matrix, verifies Core ML numeric parity, compiles the package, and installs `IronScanPallorClassifier.mlpackage` plus `pallor_manifest.json`. Color jitter is excluded because mucosal color is the target signal.

## Multimodal research suite

`multimodal_ingestion.py` performs a dry-run-first sweep of the explicitly supported local repositories. It selects only paths with an explicit eye, nail, or tongue context and a source class, prunes code environments and chart/model asset folders, verifies JPEG/PNG decoding, computes exact and perceptual hashes, excludes conflicting duplicates, and prefixes copied filenames with source provenance. Private participant groups and TongueDX source paths are hashed before manifest output. `TonguePale` may be included only with `--allow-visual-proxy-labels`; it is recorded as a visual-pallor proxy rather than anemia ground truth. Apply mode requires a reviewed permission reference for every included source and never deletes source files.

The ingestion script also recognizes a local `Eyes-Defy-Anemia` folder. It reads the first worksheet of the Italy and India metadata files without exporting raw laboratory values, selects one palpebral image per usable source participant, applies adult sex-specific hemoglobin screening thresholds, and retains pseudonymized source participant groups as similarity-clustering anchors. Malformed source PNG containers are normalized only in the private copied dataset.

Run the read-only audit:

```bash
MLTraining/.venv/bin/python -m MLTraining.scripts.multimodal_ingestion \
  --documents-root ~/Documents \
  --allow-visual-proxy-labels
```

After reviewing source permissions, construct a new output directory by adding `--apply` and one `--permission SOURCE_KEY=REVIEW_REFERENCE` argument for every source listed by the audit. The script refuses to overwrite an existing `~/Documents/IronScanMultiModalDataset` directory. `--allow-synthetic-participant-groups` is an educational-demo-only escape hatch for external eye and nail rows lacking participant metadata; it clusters deterministic grayscale-structure and color-histogram features within each source/tissue, assigns one synthetic group to each appearance cluster, and never changes the source files. This reduces close-variant leakage but does not establish participant identity.

`train_multimodal_suite.py` trains independent MobileNetV3-Small eye, nail, and tongue engineering fixtures. It refuses every training-eligible row without a participant group, creates deterministic group-separated train/validation/test splits, calculates training-only class weights, fits validation-only Platt calibration and thresholds, performs one-time test evaluation, checks Core ML probability parity within `0.01`, and compiles each package. Eye preprocessing uses the manifest-locked center crop; nail and tongue use scale-fill. Color jitter is intentionally absent.

Models train with dropout probability `0.2`. The exported Core ML graph evaluates 30 fixed classifier-head dropout masks in one call and emits `raw_proxy_logit`, `calibrated_proxy_probability`, and `predictive_uncertainty`. Fixed masks provide deterministic Swift/Python parity rather than fresh stochastic draws. When clinical Eye rows are available, Eye training excludes external proxy classes and installs `IronScanEye_Clinical.mlpackage` plus `eye_clinical_manifest.json`.

Multimodal manifests also lock `uncertaintyThreshold` and `uncertaintyPassCount`. The clinical Eye preprocessing version `multimodal-eye-clinical-2.1.0` identifies the iOS Vision lower-eyelid ROI adapter; changing that adapter requires another preprocessing and model version update plus Swift/Python parity review.

```bash
MLTraining/.venv/bin/python -m MLTraining.scripts.train_multimodal_suite \
  --dataset-root ~/Documents/IronScanMultiModalDataset \
  --allow-synthetic-participant-groups \
  --allow-dirty
```

Add `--install` only after reviewing all reports. Installation writes `IronScanEye.mlpackage`, `IronScanNail.mlpackage`, and `IronScanTongue.mlpackage` under `Models/CoreML/` plus one required manifest per model. Training rejects synthetically grouped rows unless the same explicit demo flag is supplied. These groups keep accepted appearance clusters wholly within one split but cannot establish participant-independent evaluation and therefore keep every export at `engineeringFixture` status.

Use repeatable `--tissue Eye`, `--tissue Nail`, or `--tissue Tongue` arguments to retrain only selected packages. Similarity groups are split-disjoint, but the resulting evaluation remains a source-proxy engineering test rather than participant-independent validation.
