import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";
import { dispatchJob } from "./dispatch.mjs";

const MILLISECONDS_PER_SECOND = 1000;
const secrets = new SecretsManagerClient();

export const handler = async (event) => {
  const { SecretString: privateKey } = await secrets.send(new GetSecretValueCommand({ SecretId: process.env.SECRET_ID }));
  await dispatchJob({
    appId: process.env.APP_ID,
    installationId: process.env.INSTALLATION_ID,
    privateKey,
    fetch,
    nowSeconds: Math.floor(Date.now() / MILLISECONDS_PER_SECOND),
    job: event?.job,
  });
};
