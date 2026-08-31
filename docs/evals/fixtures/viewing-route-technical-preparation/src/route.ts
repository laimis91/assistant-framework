function selectRoute(route, effects) { effects.push(`select:${route}`); }
function highlightRoute(route, effects) { effects.push(`highlight:${route}`); }
function focusViewport(route, effects) { effects.push(`focus:${route}`); }

function applyActiveRouteEffects() {
  const effects = [];
  selectRoute("ACTIVE", effects);
  highlightRoute("ACTIVE", effects);
  focusViewport("ACTIVE", effects);
  return effects;
}

module.exports = { selectRoute, highlightRoute, focusViewport, applyActiveRouteEffects };
