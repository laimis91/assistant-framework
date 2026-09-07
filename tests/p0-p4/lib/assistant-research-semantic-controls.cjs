#!/usr/bin/env node

const fs = require("fs");
const os = require("os");
const path = require("path");
const {spawnSync} = require("child_process");
const vm = require("vm");

const [mode, root, fixturePath, group] = process.argv.slice(2);
const clone = value => JSON.parse(JSON.stringify(value));
const corePath = path.join(root || "", "tools/evals/lib/research-semantic-validator.cjs");
const modes = [
  ["delegated", "five-lens-decision-briefing-uses-storm-style-workflow"],
  ["sequential_fallback", "five-lens-sequential-fallback-preserves-process-evidence"],
  ["delegated_peer_fallback", "five-lens-delegated-lenses-sequential-peer-fallback"],
  ["quick_normalized", "five-lens-quick-normalizes-to-standard"],
  ["retained_follow_ups", "five-lens-retains-all-material-follow-ups"]
];

function loadProduction(modulePath = corePath) {
  return require(modulePath);
}

function observeImport(modulePath) {
  const resolvedModulePath = require.resolve(modulePath);
  const beforeExit = process.exitCode;
  const originalStdoutWrite = process.stdout.write;
  const originalStderrWrite = process.stderr.write;
  const originalReadFileSync = fs.readFileSync;
  const stdout = [];
  const stderr = [];
  const validatorReads = [];
  const captureWrite = records => function capture(chunk, encoding, callback) {
    records.push(String(chunk));
    const completion = typeof encoding === "function" ? encoding : callback;
    if (typeof completion === "function") completion();
    return true;
  };
  process.stdout.write = captureWrite(stdout);
  process.stderr.write = captureWrite(stderr);
  fs.readFileSync = function observeRead(file, ...args) {
    const frames = (new Error().stack || "").split("\n");
    const loaderRead = /(?:defaultLoadImpl|loadSource|Module\._extensions)/.test(frames[2] || "");
    if (!loaderRead) validatorReads.push(file);
    return originalReadFileSync.call(this, file, ...args);
  };
  try {
    delete require.cache[resolvedModulePath];
    return {module: loadProduction(resolvedModulePath), stdout, stderr, validatorReads, exitCodeChanged: process.exitCode !== beforeExit};
  } finally {
    process.stdout.write = originalStdoutWrite;
    process.stderr.write = originalStderrWrite;
    fs.readFileSync = originalReadFileSync;
    process.exitCode = beforeExit;
  }
}

function observeControlledImport(source) {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "assistant-research-import-witness-"));
  const modulePath = path.join(tempDir, "validator.cjs");
  fs.writeFileSync(modulePath, `${source}\nmodule.exports = {validateResearchResponse: () => []};\n`);
  try {
    return observeImport(modulePath);
  } finally {
    delete require.cache[require.resolve(modulePath)];
    fs.rmSync(tempDir, {force: true, recursive: true});
  }
}

function loadPrivateApi(fixture, caseId) {
  const source = fs.readFileSync(path.join(root, "tests/p0-p4/lib/assistant-research-fixtures.sh"), "utf8");
  const program = source.split("<<'NODE'\n")[1].split("\nNODE\n")[0].split('if (operation === "canonical")')[0];
  const errors = [];
  const context = vm.createContext({
    require: name => name === "fs" ? {readFileSync: file => {
      if (file === fixturePath) return JSON.stringify(fixture);
      throw new Error(`unexpected private fixture read: ${file}`);
    }} : require(name),
    URL,
    process: {argv: ["node", "control", "validate", "response", fixturePath, caseId], exitCode: 0},
    console: {error: message => errors.push(message)}
  });
  vm.runInContext(`${program}\nglobalThis.api = {build, refreshDerived, validate};`, context, {timeout: 10000});
  return {api: context.api, errors};
}

function fixtureCase(fixture, caseId) {
  const found = fixture.cases.find(item => item.id === caseId);
  if (!found) throw new Error(`missing fixture case: ${caseId}`);
  return found;
}

function buildBase(privateApi, fixture, modeName, caseId) {
  const row = fixtureCase(fixture, caseId);
  return clone(privateApi.build(
    modeName,
    row.machine_expectations.required_substrings.join("\n"),
    JSON.stringify(row.semantic_context)
  ));
}

function cliErrors(errors) {
  return errors.length === 0 ? [] : [`five-lens semantic validation: ${[...new Set(errors)].slice(0, 12).join("; ")}`];
}

function outcome(expected, errors, label, summary) {
  const accepted = errors.length === 0;
  const passed = accepted === expected;
  if (expected && !accepted) summary.falseRejects += 1;
  if (!expected && accepted) summary.falseAccepts += 1;
  if (!passed) summary.failures.push(`${label}: expected ${expected ? "accept" : "reject"}, got ${accepted ? "accept" : "reject"}`);
  return passed;
}

function optionalUrls(validate = loadProduction().validateResearchResponse) {
  const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8"));
  const boundUrl = "https://www.iana.org/optional-verified-url";
  const controls = [
    ["omitted", true], ["empty", true, []], ["bound-public-url", true, [boundUrl]],
    ["unbound-public-url", false, ["https://www.iana.org/unbound-optional-url"]],
    ["null", false, null], ["string", false, boundUrl], ["object", false, {}],
    ["non-string-entry", false, [42]], ["mixed-non-string-entry", false, [boundUrl, null]]
  ];
  const summary = {mode: "optional-urls", checks: 0, validatorChecks: 0, falseAccepts: 0, falseRejects: 0, failures: []};

  for (const [modeName, caseId] of modes) {
    const row = fixtureCase(fixture, caseId);
    const {api: privateApi, errors: privateErrors} = loadPrivateApi(fixture, caseId);
    const base = buildBase(privateApi, fixture, modeName, caseId);
    base.findings = [{finding: `${row.semantic_context.required_topic_terms.join("; ")}: Optional verified URL control.`, confidence: "low", sources: ["source:optional-verified-url"]}];
    base.five_lens_process_evidence.peer_review_input_binding.verified_source_evidence.push({
      claim: "Bound optional URL evidence.", source: "source:optional-verified-url", verification_method: "public_url",
      verification_reference: boundUrl, verified_url: boundUrl, verification_detail: "Retained static URL-binding control."
    });
    for (const [name, expected, value] of controls) {
      const response = clone(base);
      if (name !== "omitted") response.findings[0].verified_urls = clone(value);
      privateErrors.length = 0;
      privateApi.refreshDerived(response);
      const privateAccepted = privateApi.validate(response);
      const errors = validate(response, row);
      const expectedErrors = expected ? [] : ["final artifacts: finding shape"];
      const classificationPassed = outcome(expected, errors, `${modeName}/${name}`, summary);
      const passed = classificationPassed
        && privateAccepted === expected
        && JSON.stringify(privateErrors) === JSON.stringify(expected ? [] : ["artifacts:findings"])
        && JSON.stringify(errors) === JSON.stringify(expectedErrors)
        && JSON.stringify(cliErrors(errors)) === JSON.stringify(expected ? [] : ["five-lens semantic validation: final artifacts: finding shape"]);
      console.log(JSON.stringify({mode: modeName, control: name, expected, privateAccepted, privateErrors: [...privateErrors], errors, passed}));
      if (!passed) summary.failures.push(`${modeName}/${name}: diagnostic mismatch`);
      summary.checks += 1;
      summary.validatorChecks += 2;
    }
  }
  return summary;
}

function setVerdict(response, verdict) {
  const peer = response.peer_review;
  const evidence = response.five_lens_process_evidence;
  peer.verdict = verdict;
  peer.status = verdict === "accepted" ? "DONE" : "DONE_WITH_CONCERNS";
  evidence.peer_review_input_binding.initial_synthesis = clone(response.synthesis_briefing);
  peer.required_revisions = [];
  delete peer.revision_disposition_id;
  delete peer.revision_disposition;
  delete evidence.peer_review_revision_disposition_id;
  if (verdict !== "revise") return;
  evidence.peer_review_input_binding.initial_synthesis.executive_summary += " Initial draft pending review.";
  peer.required_revisions = ["Calibrate the initial claim"];
  peer.revision_disposition_id = evidence.peer_review_revision_disposition_id = "revision-control";
  peer.revision_disposition = [{required_revision: peer.required_revisions[0], outcome: "claim_downgraded", closure_evidence: "Final claim calibrated.", resulting_synthesis_digest: evidence.final_synthesis_digest}];
}

function completionControls(validate = loadProduction().validateResearchResponse, selectedGroup = group) {
  const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8"));
  let privateApi;
  let privateErrors;
  const summary = {mode: `completion/${selectedGroup}`, checks: 0, validatorChecks: 0, falseAccepts: 0, falseRejects: 0, failures: []};
  const evaluate = (modeName, name, expected, response, row, expectedPrivate = [], expectedErrors = []) => {
    privateErrors.length = 0;
    privateApi.refreshDerived(response);
    const privateAccepted = privateApi.validate(response);
    const errors = validate(response, row);
    const classificationPassed = outcome(expected, errors, `${modeName}/${name}`, summary);
    const passed = classificationPassed
      && privateAccepted === expected
      && JSON.stringify(privateErrors) === JSON.stringify(expectedPrivate)
      && JSON.stringify(errors) === JSON.stringify(expectedErrors)
      && outcome(expected, errors, `${modeName}/${name}`, summary);
    console.log(JSON.stringify({group: selectedGroup, mode: modeName, control: name, expected, privateAccepted, privateErrors: [...privateErrors], errors, passed}));
    if (!passed) summary.failures.push(`${modeName}/${name}: diagnostic mismatch`);
    summary.checks += 1;
    summary.validatorChecks += 2;
  };

  if (selectedGroup === "peer") {
    for (const [modeName, caseId] of modes) {
      const row = fixtureCase(fixture, caseId);
      ({api: privateApi, errors: privateErrors} = loadPrivateApi(fixture, caseId));
      const base = buildBase(privateApi, fixture, modeName, caseId);
      for (const verdict of ["accepted", "accepted_with_concerns", "revise"]) {
        const valid = clone(base);
        setVerdict(valid, verdict);
        evaluate(modeName, verdict, true, valid, row);
        if (verdict === "revise") continue;
        for (const [owner, field, value] of [
          ["peer_review", "revision_disposition_id", "unexpected-closure"], ["peer_review", "revision_disposition", []],
          ["five_lens_process_evidence", "peer_review_revision_disposition_id", "unexpected-closure"],
          ["peer_review", "revision_disposition_id", null], ["peer_review", "revision_disposition", null],
          ["five_lens_process_evidence", "peer_review_revision_disposition_id", null]
        ]) {
          const response = clone(valid);
          response[owner][field] = value;
          const errors = owner === "peer_review"
            ? ["peer review: accepted revision closure", "peer review: non-revise revision closure leakage"]
            : ["peer review: non-revise revision closure leakage"];
          evaluate(modeName, `${verdict}/${field}/${value === null ? "null" : "present"}`, false, response, row,
            ["peer:status-and-revision-truth-table"], errors);
        }
      }
    }
  } else if (selectedGroup === "capacity") {
    const [modeName, caseId] = modes[1];
    const row = fixtureCase(fixture, caseId);
    ({api: privateApi, errors: privateErrors} = loadPrivateApi(fixture, caseId));
    const base = buildBase(privateApi, fixture, modeName, caseId);
    for (const [name, value, expected] of [["one", 1, true], ["two", 2, true], ["max-safe", 9007199254740991, true],
      ["fraction-one-half", 1.5, false], ["fraction-half", 0.5, false], ["string", "2", false], ["zero", 0, false], ["overflow", 9007199254740992, false]]) {
      const response = clone(base);
      const controlFixture = clone(fixture);
      const controlRow = fixtureCase(controlFixture, caseId);
      controlRow.semantic_context.adapter_context.max_concurrent_lens_workers = value;
      ({api: privateApi, errors: privateErrors} = loadPrivateApi(controlFixture, caseId));
      evaluate(modeName, name, expected, response, controlRow,
        expected ? [] : ["semantic-context:fixture-shape"], expected ? [] : ["semantic context: required shape"]);
    }
  } else if (selectedGroup === "findings") {
    const [modeName, caseId] = modes[1];
    const row = fixtureCase(fixture, caseId);
    ({api: privateApi, errors: privateErrors} = loadPrivateApi(fixture, caseId));
    const base = buildBase(privateApi, fixture, modeName, caseId);
    const findingsError = ["final artifacts: findings required unless evidence-empty completion has gaps"];
    const firstResult = response => response.five_lens_process_evidence.accepted_lens_results[0];
    const check = (name, expected, mutate, privateReason = [], errors = []) => {
      const response = clone(base);
      mutate(response, firstResult(response));
      evaluate(modeName, name, expected, response, row, privateReason, errors);
    };
    evaluate(modeName, "evidence-empty-with-gaps", true, clone(base), row);
    const noneNeeded = {decision: "none_needed", answer_or_gap: "The retained research index supports no additional material follow-up.", sources_or_verified_urls: ["source:research-index"], evidence_status: "source_backed", gaps: []};
    const optionalFinding = {finding: "The research index documents collection coverage.", confidence: "low", sources: noneNeeded.sources_or_verified_urls};
    check("sourced-none-needed-without-finding", true, (response, result) => { result.follow_ups = [clone(noneNeeded)]; });
    check("sourced-none-needed-with-optional-finding", true, (response, result) => { result.follow_ups = [clone(noneNeeded)]; response.findings = [clone(optionalFinding)]; });
    for (const evidenceStatus of ["inference_only", "unresolved"]) {
      check(`source-empty-none-needed/${evidenceStatus}`, true, (response, result) => { result.follow_ups[0].evidence_status = evidenceStatus; });
      check(`source-empty-material-follow-up/${evidenceStatus}`, true, (response, result) => { Object.assign(result.follow_ups[0], {decision: "follow_up", question: "Which source remains unconfirmed?", evidence_status: evidenceStatus}); });
    }
    check("empty-findings-without-top-level-gaps", false, response => { response.gaps = []; }, ["artifacts:findings"], findingsError);
    check("sourced-main-result-without-finding", false, (response, result) => { result.sources_or_verified_urls = ["source:main-result"]; result.evidence_status = "source_backed"; }, ["artifacts:findings"], findingsError);
    const followUpError = (privateReason, productionReason) => [[privateReason], [`accepted result practitioner${productionReason}`]];
    const [exclusivePrivate, exclusiveProduction] = followUpError("follow-ups:exclusive-none-needed", ": follow-up none_needed exclusivity");
    check("none-needed-mixed-with-material-follow-up", false, (response, result) => { result.follow_ups.push({...clone(result.follow_ups[0]), decision: "follow_up", question: "Which source remains unconfirmed?"}); }, exclusivePrivate, exclusiveProduction);
    check("duplicate-none-needed", false, (response, result) => { result.follow_ups.push(clone(result.follow_ups[0])); }, exclusivePrivate, exclusiveProduction);
    const [gapPrivate, gapProduction] = followUpError("follow-up:own-gaps", " follow-up: nonblank gaps array required");
    check("none-needed-malformed-own-gap", false, (response, result) => { result.follow_ups[0].gaps = [""]; }, gapPrivate, gapProduction);
    for (const decision of ["none_needed", "follow_up"]) {
      const setDecision = result => { result.follow_ups[0].decision = decision; if (decision === "follow_up") result.follow_ups[0].question = "Which source remains unconfirmed?"; };
      const [emptyPrivate, emptyProduction] = followUpError("sources:follow-up", " follow-up: empty non-source evidence requires a gap");
      check(`${decision}/empty-sources-without-own-gap`, false, (response, result) => { setDecision(result); result.follow_ups[0].gaps = []; }, emptyPrivate, emptyProduction);
      const [sourcePrivate, sourceProduction] = followUpError("sources:follow-up", " follow-up: source-backed result requires a source");
      check(`${decision}/source-backed-without-source`, false, (response, result) => { setDecision(result); result.follow_ups[0].evidence_status = "source_backed"; response.findings = [{finding: "The retained fixture documents decision evidence.", confidence: "low", sources: ["source:research-corpus:summary"]}]; }, sourcePrivate, sourceProduction);
    }
    const material = clone(base);
    const followUp = {decision: "follow_up", question: "What independent source changes this decision?", answer_or_gap: "Independent evidence supports further investigation.", sources_or_verified_urls: ["source:material-follow-up"], evidence_status: "source_backed", gaps: []};
    material.five_lens_process_evidence.accepted_lens_results[0].follow_ups = [followUp];
    material.findings = [{finding: "The material follow-up supports further investigation.", confidence: "low", sources: followUp.sources_or_verified_urls}];
    evaluate(modeName, "material-follow-up-with-finding", true, clone(material), row);
    material.findings = [];
    evaluate(modeName, "material-follow-up-without-finding", false, material, row, ["artifacts:findings"], findingsError);
  } else {
    throw new Error(`unknown completion group: ${selectedGroup}`);
  }
  return summary;
}

function isolation() {
  const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8"));
  const realImport = observeImport(corePath);
  const {validateResearchResponse} = realImport.module;
  const importRead = observeControlledImport('require("fs").readFileSync(__filename, "utf8");');
  const importStdout = observeControlledImport('console.log("UNEXPECTED IMPORT STDOUT");');
  const importStderr = observeControlledImport('console.error("UNEXPECTED IMPORT STDERR");');
  const importExit = observeControlledImport("process.exitCode = process.exitCode === 1 ? 0 : 1;");
  const summary = {mode: "isolation", checks: 0, validatorChecks: 0, falseAccepts: 0, falseRejects: 0, failures: []};
  const delegated = fixtureCase(fixture, modes[0][1]);
  const fallback = fixtureCase(fixture, modes[1][1]);
  const {api: privateApi} = loadPrivateApi(fixture, delegated.id);
  const valid = buildBase(privateApi, fixture, modes[0][0], delegated.id);
  const fixtureBefore = JSON.stringify(delegated);
  const validBefore = JSON.stringify(valid);
  const firstErrors = validateResearchResponse(valid, delegated);
  const invalid = clone(valid);
  invalid.findings[0].verified_urls = null;
  privateApi.refreshDerived(invalid);
  const invalidErrors = validateResearchResponse(invalid, delegated);
  const finalErrors = validateResearchResponse(valid, delegated);
  const fallbackResponse = buildBase(privateApi, fixture, modes[1][0], fallback.id);
  const fallbackErrors = validateResearchResponse(fallbackResponse, fallback);
  const missingCandidate = clone(valid);
  delete missingCandidate.candidate_mechanisms;
  const missingBefore = JSON.stringify(missingCandidate);
  const missingErrors = validateResearchResponse(missingCandidate, delegated);
  const heldOutInvalid = clone(valid);
  heldOutInvalid.candidate_mechanisms = "not-an-array";
  privateApi.refreshDerived(heldOutInvalid);
  const heldOutInvalidBefore = JSON.stringify(heldOutInvalid);
  const heldOutInvalidErrors = validateResearchResponse(heldOutInvalid, delegated);
  const checks = [
    ["side-effect-free-import", realImport.stdout.length === 0 && realImport.stderr.length === 0 && realImport.validatorReads.length === 0 && !realImport.exitCodeChanged],
    ["import-read-witness", importRead.validatorReads.length === 1 && importRead.stdout.length === 0 && importRead.stderr.length === 0 && !importRead.exitCodeChanged],
    ["import-stdout-witness", importStdout.stdout.length === 1 && importStdout.stderr.length === 0 && importStdout.validatorReads.length === 0 && !importStdout.exitCodeChanged],
    ["import-stderr-witness", importStderr.stdout.length === 0 && importStderr.stderr.length === 1 && importStderr.validatorReads.length === 0 && !importStderr.exitCodeChanged],
    ["import-exit-witness", importExit.stdout.length === 0 && importExit.stderr.length === 0 && importExit.validatorReads.length === 0 && importExit.exitCodeChanged],
    ["initial-valid", firstErrors.length === 0],
    ["invalid-between-valid", JSON.stringify(invalidErrors) === JSON.stringify(["final artifacts: finding shape"])],
    ["final-valid", finalErrors.length === 0],
    ["fresh-error-arrays", firstErrors !== invalidErrors && invalidErrors !== finalErrors],
    ["distinct-fixture-case", fallbackErrors.length === 0],
    ["missing-candidate-mechanisms", missingErrors.length === 0],
    ["held-out-invalid-candidate-mechanisms", JSON.stringify(heldOutInvalidErrors) === JSON.stringify(["candidate mechanisms: array required"])],
    ["response-immutable", JSON.stringify(valid) === validBefore && JSON.stringify(missingCandidate) === missingBefore && JSON.stringify(heldOutInvalid) === heldOutInvalidBefore],
    ["fixture-immutable", JSON.stringify(delegated) === fixtureBefore]
  ];
  for (const [name, passed] of checks) {
    if (!passed) summary.failures.push(name);
    summary.checks += 1;
    summary.validatorChecks += 1;
  }
  console.log(JSON.stringify(summary));
  return summary;
}

function cliCompatibility() {
  const summary = {mode: "cli-compat", checks: 0, validatorChecks: 0, falseAccepts: 0, falseRejects: 0, failures: []};
  const configuredRoot = fs.mkdtempSync(path.join(os.tmpdir(), "assistant-research-cli-root-"));
  const originalTmpdir = process.env.TMPDIR;
  let tempDir;
  try {
    process.env.TMPDIR = configuredRoot;
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "assistant-research-cli-compat-"));
    const responsePath = path.join(tempDir, "response.json");
    const missingFixture = path.join(tempDir, "missing.json");
    const invalidResponse = path.join(tempDir, "invalid-response.json");
    fs.writeFileSync(responsePath, "{}");
    fs.writeFileSync(invalidResponse, "{");
    const expected = [
      ["missing-fixture", responsePath, missingFixture, "five-lens-decision-briefing-uses-storm-style-workflow", "semantic context: readable fixture case required; response: five_lens_briefing required; process: supported execution modes required"],
      ["missing-case", responsePath, fixturePath, "missing-case", "semantic context: selected fixture case required; response: five_lens_briefing required; process: supported execution modes required"],
      ["combined-fixture-and-response-parse", invalidResponse, missingFixture, "missing-case", "semantic context: readable fixture case required; response: valid JSON required"]
    ];
    for (const [name, response, fixture, caseId, diagnostic] of expected) {
      const result = spawnSync(process.execPath, [corePath, response, fixture, caseId], {encoding: "utf8"});
      const passed = result.status === 1 && result.stdout === "" && result.stderr === `five-lens semantic validation: ${diagnostic}\n`;
      if (!passed) summary.failures.push(`${name}: exit=${result.status} stderr=${JSON.stringify(result.stderr)}`);
      summary.checks += 1;
      summary.validatorChecks += 1;
    }
    if (!tempDir.startsWith(`${configuredRoot}${path.sep}`)) summary.failures.push(`temporary directory escaped configured root: ${tempDir}`);
    summary.checks += 1;
  } finally {
    if (originalTmpdir === undefined) delete process.env.TMPDIR;
    else process.env.TMPDIR = originalTmpdir;
    if (tempDir) fs.rmSync(tempDir, {force: true, recursive: true});
    fs.rmSync(configuredRoot, {force: true, recursive: true});
  }
  if (fs.existsSync(configuredRoot)) summary.failures.push(`configured temporary root was not removed: ${configuredRoot}`);
  summary.checks += 1;
  console.log(JSON.stringify(summary));
  return summary;
}

function counterAccounting() {
  const expected = [
    ["optional-accept-all", optionalUrls(() => []), 30, 0],
    ["optional-reject-all", optionalUrls(() => ["synthetic rejection"]), 0, 15],
    ["completion-accept-all", completionControls(() => [], "capacity"), 5, 0],
    ["completion-reject-all", completionControls(() => ["synthetic rejection"], "capacity"), 0, 3]
  ];
  const summary = {mode: "counter-accounting", checks: 0, validatorChecks: 0, falseAccepts: 0, falseRejects: 0, failures: []};
  for (const [name, result, falseAccepts, falseRejects] of expected) {
    if (result.falseAccepts !== falseAccepts || result.falseRejects !== falseRejects) summary.failures.push(`${name}: ${result.falseAccepts}/${result.falseRejects}`);
    summary.checks += 1;
  }
  console.log(JSON.stringify(summary));
  return summary;
}

function run() {
  let summary;
  if (mode === "--optional-urls") summary = optionalUrls();
  else if (mode === "--completion") summary = completionControls();
  else if (mode === "--isolation") summary = isolation();
  else if (mode === "--cli-compat") summary = cliCompatibility();
  else if (mode === "--counter-accounting") summary = counterAccounting();
  else throw new Error("usage: assistant-research-semantic-controls.cjs --optional-urls|--completion|--isolation|--cli-compat|--counter-accounting ROOT FIXTURE [GROUP]");
  console.log(JSON.stringify(summary));
  if (summary.failures.length > 0 || summary.falseAccepts > 0 || summary.falseRejects > 0) process.exitCode = 1;
}

run();
