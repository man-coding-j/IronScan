# App layout and Congressional App Challenge intro update

The affected History, Learn, Profile, and active persistent scan content now use full-width vertical scroll containers, symmetric 20-point side padding, and 12-point top padding. Safe-area expansion stays on decorative backgrounds. Profile's duplicate 16-point outer inset was removed, and Learn's featured card fills its available width.

Camera images and captured thumbnails now render within measured bounds, preventing intrinsic image dimensions from widening their parent layout. The active scan suite uses a 3:4 portrait preview, one alignment pill, and the existing camera controls. The eye guide is an ellipse. View-model startup is suppressed only in the explicitly enabled simulator capture fixture.

Home and History now read the same `ScanHistoryStore.records` that supplies the sync indicator; they no longer combine a count from one store with a latest reading from another. Estimated hemoglobin is shown in the latest-reading title when available. Vitals is immediately below the Home result, and History exposes Export and Recent History directly below the trend. The requested DEMO labels were removed while explanatory simulated-data copy remains.

The intro uses fresh native captures rather than painting readings or layout fixes over screenshots. Its editable config, README, render verification, and MP4 are in `Video/IronScanIntro/`. All five captures use seven deterministic fictional readings ending at 11.8 g/dL / Mild. They are local and gitignored. No participant data or raw tongue image was added.

Validation: app simulator build and the focused fictional-fixture XCTest passed; TypeScript and asset checks passed; representative frames were visually inspected; the 29.2-second silent MP4 was probed and fully decoded. See `Video/IronScanIntro/VALIDATION.md` for precise scope and physical-device assumptions.
