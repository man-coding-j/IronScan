# Smart Color Calibration specification

IronScan calibration version `1.0.0` operates entirely on local, orientation-normalized pixel buffers. It never creates JPEG or PNG intermediates. Core Image converts the capture into extended linear sRGB with deterministic 1/255 linear-channel quantization, vImage resizes the segmentation mask, LAPACK solves the regularized weighted matrix, and SIMD applies the matrix per pixel.

## Reference observations

Reference locations are normalized rectangles supplied by the capture protocol. The implementation removes a 12% border, pixels at or above `0.98` in any linear channel, luminance at or below `0.025`, and samples farther than `0.12` Euclidean linear-RGB units from the initial channel median. At least three usable card patches are required for a full matrix.

For observed row vectors `P`, target row vectors `T`, diagonal weights `W`, and `lambda = 0.001`, solve without forming an inverse:

`(Pᵀ W P + lambda I) M = Pᵀ W T + lambda I`

The Swift implementation uses LAPACK Cholesky solve `dposv`. The reported condition number is the square root of the regularized normal matrix's largest-to-smallest eigenvalue ratio. Corrected row-vector pixels are `p M`.

## Locked rejection thresholds

- condition number greater than `250`
- median CIE76 reference residual greater than `8`
- maximum CIE76 reference residual greater than `15`
- tongue area below `4%`
- tongue mask touching the one-pixel invalid boundary
- specular fraction greater than `12%`
- tongue luminance p90–p10 spread divided by median greater than `0.45`
- unlocked focus, exposure, or white balance; unknown source color space; or exposure target offset magnitude above `0.35`

Specular pixels require linear value at least `0.92` and channel range at most `0.06`. They are removed from the eroded central ROI. Optional exposure normalization targets configured tongue median luminance and is clamped to `[0.8, 1.25]`.

## Fallback modes

A single configured neutral patch or cohort-derived tooth pseudo-reference fits diagonal gains only. Gains are clamped to `[0.8, 1.2]` and rescaled to preserve observed mean luminance. Accepted multi-patch, neutral-patch, and teeth pseudo-reference modes report calibration confidence `1.0`, `0.7`, and `0.5`, respectively. Teeth are never forced to pure white and remain a distinct lower-confidence mode. Missing or unstable references produce `uncalibratedRejected` with confidence `0`; rejected samples cannot enter risk inference.

## TongueDX limitation

The locally supplied TongueDX copy contains JPEG images and phenotype CSVs but no calibration targets, capture metadata, laboratory hemoglobin labels, license, or consent documentation. It is not used to derive calibration targets, golden outputs, or anemia-risk labels.
