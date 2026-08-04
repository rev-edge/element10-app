# Element 10 — headless evidence harness

Produces four of the protocol's five evidence classes with **no browser**:
interaction, mutator, persisted-state, boundary. Render (screenshots) is the
only class that requires a renderer.

    npm install          # once
    node e10_harness.js <path-to-08-product-workspace.html> [scenario.js]

Exit code 0 = all pass, 1 = any failure (CI-usable). Scenarios drive REAL DOM
events (mousedown → mouseup → click, input events), so in-flight-interaction
defects — the caret-loss and click-target families — actually reproduce.

Why this exists: a wedged preview environment once blocked an entire track.
Evidence production must never be single-homed. A renderer outage now degrades
the render class only; the gate continues on the other four with the gap
disclosed honestly.
