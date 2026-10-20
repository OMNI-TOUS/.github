import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";
import { dispatchSync } from "./dispatch.mjs";

const MILLISECONDS_PER_SECOND = 1000;
const secrets = new SecretsManagerClient();

export const handler = async () => {
  const { SecretString: privateKey } = await secrets.send(new GetSecretValueCommand({ SecretId: process.env.SECRET_ID }));
  await dispatchSync({
    appId: process.env.APP_ID,
    installationId: process.env.INSTALLATION_ID,
    privateKey,
    fetch,
    nowSeconds: Math.floor(Date.now() / MILLISECONDS_PER_SECOND),
  });
};
