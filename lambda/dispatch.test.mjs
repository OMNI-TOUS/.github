import { test } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, createVerify } from "node:crypto";
import { appJwt, dispatchJob } from "./dispatch.mjs";

const { privateKey, publicKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  privateKeyEncoding: { type: "pkcs1", format: "pem" },
  publicKeyEncoding: { type: "spki", format: "pem" },
});

const NOW_SECONDS = 1_800_000_000;
const APP_ID = "5387222";
const INSTALLATION_ID = "173178335";

const decode = (part) => JSON.parse(Buffer.from(part, "base64url").toString());

const fakeFetch = (responses) => {
  const calls = [];
  const fetch = async (url, options) => {
    calls.push({ url, options, body: options.body && JSON.parse(options.body) });
    return responses[calls.length - 1];
  };
  return { fetch, calls };
};

const tokenResponse = { ok: true, status: 201, json: async () => ({ token: "ghs_installation" }) };
const dispatchResponse = { ok: true, status: 204 };

test("appJwt signs an RS256 token issued by the app", () => {
  const [header, payload, signature] = appJwt(APP_ID, privateKey, NOW_SECONDS).split(".");

  assert.deepEqual(decode(header), { alg: "RS256", typ: "JWT" });
  assert.deepEqual(decode(payload), { iat: NOW_SECONDS - 60, exp: NOW_SECONDS + 540, iss: APP_ID });
  const verifier = createVerify("RSA-SHA256").update(`${header}.${payload}`);
  assert.ok(verifier.verify(publicKey, signature, "base64url"));
});

test("dispatchJob gets an actions-only token for the .github repo", async () => {
  const { fetch, calls } = fakeFetch([tokenResponse, dispatchResponse]);

  await dispatchJob({ appId: APP_ID, installationId: INSTALLATION_ID, privateKey, fetch, nowSeconds: NOW_SECONDS });

  assert.equal(calls[0].url, `https://api.github.com/app/installations/${INSTALLATION_ID}/access_tokens`);
  assert.equal(calls[0].options.method, "POST");
  assert.match(calls[0].options.headers.Authorization, /^Bearer [\w-]+\.[\w-]+\.[\w-]+$/);
  assert.deepEqual(calls[0].body, { repositories: [".github"], permissions: { actions: "write" } });
});

test("dispatchJob starts a real sync run on main", async () => {
  const { fetch, calls } = fakeFetch([tokenResponse, dispatchResponse]);

  await dispatchJob({ appId: APP_ID, installationId: INSTALLATION_ID, privateKey, fetch, nowSeconds: NOW_SECONDS });

  assert.equal(calls[1].url, "https://api.github.com/repos/OMNI-TOUS/.github/actions/workflows/org-sync.yml/dispatches");
  assert.equal(calls[1].options.method, "POST");
  assert.equal(calls[1].options.headers.Authorization, "Bearer ghs_installation");
  assert.deepEqual(calls[1].body, { ref: "main", inputs: { job: "sync", "dry-run": "false" } });
});

test("dispatchJob starts the job it is given", async () => {
  const { fetch, calls } = fakeFetch([tokenResponse, dispatchResponse]);

  await dispatchJob({ appId: APP_ID, installationId: INSTALLATION_ID, privateKey, fetch, nowSeconds: NOW_SECONDS, job: "weekly" });

  assert.deepEqual(calls[1].body, { ref: "main", inputs: { job: "weekly", "dry-run": "false" } });
});

test("dispatchJob fails when GitHub rejects the token request", async () => {
  const { fetch, calls } = fakeFetch([{ ok: false, status: 401 }]);

  await assert.rejects(
    dispatchJob({ appId: APP_ID, installationId: INSTALLATION_ID, privateKey, fetch, nowSeconds: NOW_SECONDS }),
    /401/,
  );
  assert.equal(calls.length, 1);
});

test("dispatchJob fails when GitHub rejects the dispatch", async () => {
  const { fetch } = fakeFetch([tokenResponse, { ok: false, status: 403 }]);

  await assert.rejects(
    dispatchJob({ appId: APP_ID, installationId: INSTALLATION_ID, privateKey, fetch, nowSeconds: NOW_SECONDS }),
    /403/,
  );
});
