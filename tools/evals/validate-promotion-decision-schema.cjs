#!/usr/bin/env node

const fs = require("node:fs");
const Ajv2020 = require("ajv/dist/2020").default;

const [schemaPath, ...documentPaths] = process.argv.slice(2);
if (!schemaPath || documentPaths.length === 0) {
  console.error("usage: validate-promotion-decision-schema.cjs SCHEMA DOCUMENT...");
  process.exit(2);
}

const validator = new Ajv2020({ allErrors: true, strict: false }).compile(
  JSON.parse(fs.readFileSync(schemaPath, "utf8")),
);
for (const documentPath of documentPaths) {
  if (!validator(JSON.parse(fs.readFileSync(documentPath, "utf8")))) {
    console.error(`${documentPath}: ${JSON.stringify(validator.errors)}`);
    process.exit(1);
  }
}
