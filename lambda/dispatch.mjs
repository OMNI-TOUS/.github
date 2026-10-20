import { createSign } from "node:crypto";

const GITHUB_API = "https://api.github.com";
const API_VERSION = "2022-11-28";
const ORG = "OMNI-TOUS";
const REPO = ".github";
const WORKFLOW = "org-sync.yml";
const BRANCH = "main";
const DEFAULT_JOB = "sync";
const CLOCK_SKEW_SECONDS = 60;
const JWT_LIFETIME_SECONDS = 540;

const base64url = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");

export const appJwt = (appId, privateKey, nowSeconds) => {
  const header = base64url({ alg: "RS256", typ: "JWT" });
  const payload = base64url({
    iat: nowSeconds - CLOCK_SKEW_SECONDS,
    exp: nowSeconds + JWT_LIFETIME_SECONDS,
    iss: appId,
  });
  const signature = createSign("RSA-SHA256").update(`${header}.${payload}`).sign(privateKey, "base64url");
  return `${header}.${payload}.${signature}`;
};

const post = async (fetch, path, bearer, body) => {
  const response = await fetch(`${GITHUB_API}${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${bearer}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": API_VERSION,
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    throw new Error(`POST ${path} failed with ${response.status}`);
  }
  return response;
};

const installationToken = async ({ appId, installationId, privateKey, fetch, nowSeconds }) => {
  const response = await post(fetch, `/app/installations/${installationId}/access_tokens`, appJwt(appId, privateKey, nowSeconds), {
    repositories: [REPO],
    permissions: { actions: "write" },
  });
  return (await response.json()).token;
};

export const dispatchJob = async ({ job = DEFAULT_JOB, ...options }) => {
  const token = await installationToken(options);
  await post(options.fetch, `/repos/${ORG}/${REPO}/actions/workflows/${WORKFLOW}/dispatches`, token, {
    ref: BRANCH,
    inputs: { job, "dry-run": "false" },
  });
};
