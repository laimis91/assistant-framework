export function foregroundRead({ stale, cancelled, retryResult = "fresh" }) {
  if (!stale) return ["fresh"];
  if (cancelled) return ["stale", "cancelled"];
  return ["stale", "retrying", retryResult];
}

export function backgroundRefresh({ stale, cancelled }) {
  if (!stale) return ["fresh"];
  if (cancelled) return ["stale", "cancelled"];
  return ["stale", "queued", "fresh"];
}
