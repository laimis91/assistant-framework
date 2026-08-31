const test = require("node:test");
const assert = require("node:assert/strict");
const { applyActiveRouteEffects } = require("../src/route.ts");

test("ACTIVE route selects, highlights, and focuses the viewport", () => {
  assert.deepEqual(applyActiveRouteEffects(), ["select:ACTIVE", "highlight:ACTIVE", "focus:ACTIVE"]);
});
