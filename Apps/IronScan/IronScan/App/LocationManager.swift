@@
-    private func searchNearby(centeredAt location: CLLocation) async {
+    private func searchNearby(centeredAt location: CLLocation) async {
@@
-            do {
-                let response = try await MKLocalSearch(request: request).start()
-                results.append(contentsOf: response.mapItems.compactMap {
-                    facility(from: $0, relativeTo: location)
-                })
-            } catch {
-                searchFailureCount += 1
-            }
+            do {
+                // Keep MapKit usage on the MainActor since MKLocalSearch.Response is not Sendable
+                let response = try await performLocalSearch(request)
+                results.append(contentsOf: response.mapItems.compactMap {
+                    facility(from: $0, relativeTo: location)
+                })
+            } catch {
+                searchFailureCount += 1
+            }
         }
@@
 }
-
-private func performLocalSearch(_ request: MKLocalSearch.Request) async throws -> MKLocalSearch.Response {
-    try await withCheckedThrowingContinuation { continuation in
-        MKLocalSearch(request: request).start { response, error in
-            if let response {
-                continuation.resume(returning: response)
-            } else {
-                continuation.resume(throwing: error ?? URLError(.unknown))
-            }
-        }
-    }
-}
+
+@MainActor
+private func performLocalSearch(_ request: MKLocalSearch.Request) async throws -> MKLocalSearch.Response {
+    try await withCheckedThrowingContinuation { continuation in
+        MKLocalSearch(request: request).start { response, error in
+            if let response {
+                continuation.resume(returning: response)
+            } else {
+                continuation.resume(throwing: error ?? URLError(.unknown))
+            }
+        }
+    }
+}
