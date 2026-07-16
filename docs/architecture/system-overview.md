# System overview

IronScan is a non-clinical research prototype. The SwiftUI iOS application captures a standardized image, performs segmentation and deterministic color calibration, and runs Core ML risk inference locally. The optional FastAPI server stores anonymous engineering metrics only and is not required for inference.

Raw images remain local unless Developer Mode and debug image uploads are both explicitly enabled. Rejected calibration produces `Unable to assess` and does not invoke risk inference.
