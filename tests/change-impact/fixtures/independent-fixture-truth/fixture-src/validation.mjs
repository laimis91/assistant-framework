export function normalizeOptional(value) {
  if (value === null) return null;
  return String(value).trim();
}

export function formSubmit(value) {
  const normalized = normalizeOptional(value);
  if (normalized === null) return { state: "untouched" };
  if (normalized === "") return { state: "required-error" };
  return { state: "submitted", value: normalized };
}

export function bulkImport(value) {
  const normalized = normalizeOptional(value);
  if (normalized === null) return { state: "use-default-mapping" };
  if (normalized === "") return { state: "no-column-error" };
  return { state: "map-column", value: normalized };
}

export const equivalentFormConsumers = ["form-submit", "form-draft", "form-accessibility"];
export function equivalentFormConsumer(value) { return formSubmit(value); }
