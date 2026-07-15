# IronScan repository instructions

- Treat IronScan as a non-clinical research prototype.
- Keep raw tongue images local outside explicitly enabled Developer Mode.
- Use Swift strict concurrency and keep camera, inference, disk, and UI work on their designated actors.
- Never add real participant data or diagnostic language.
- Keep model preprocessing synchronized with manifests and Python/Swift parity fixtures.
- Record unresolved validation and physical-device assumptions honestly.
