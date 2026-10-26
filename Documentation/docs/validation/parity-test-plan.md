# Parity test plan

Swift and Python fixtures must use identical manifests and preprocessing versions. Required tolerances are probability absolute difference at most `0.01`, no locked-fixture decision mismatch, segmentation Dice at least `0.99`, and documented tensor tolerance. Any preprocessing change requires new manifests, fixtures, tests, and model versions.
