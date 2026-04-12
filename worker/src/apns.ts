/**
 * APNs push notification sender using JWT (ES256) authentication.
 * Uses Web Crypto API — no Node.js dependencies.
 */

interface APNsConfig {
  keyId: string;
  teamId: string;
  privateKey: string; // PEM-encoded .p8 key content
  bundleId: string;
  useSandbox?: boolean; // true = api.sandbox.push.apple.com
}

interface APNsPushOptions {
  token: string;
  payload: Record<string, unknown>;
  pushType: "liveactivity";
  topic: string;
  priority?: number;
}

// Cache the imported key and JWT token
let cachedKey: CryptoKey | null = null;
let cachedJwt: { token: string; expiry: number } | null = null;

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  if (cachedKey) return cachedKey;

  // Strip PEM headers and decode base64
  const stripped = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");

  const binaryStr = atob(stripped);
  const bytes = new Uint8Array(binaryStr.length);
  for (let i = 0; i < binaryStr.length; i++) {
    bytes[i] = binaryStr.charCodeAt(i);
  }

  cachedKey = await crypto.subtle.importKey(
    "pkcs8",
    bytes.buffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
  return cachedKey;
}

function base64url(data: ArrayBuffer | Uint8Array | string): string {
  let b64: string;
  if (typeof data === "string") {
    b64 = btoa(data);
  } else {
    const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
    let binary = "";
    for (const byte of bytes) {
      binary += String.fromCharCode(byte);
    }
    b64 = btoa(binary);
  }
  return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function generateJWT(config: APNsConfig): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  // Reuse cached JWT if still valid (tokens last 1 hour, refresh at 50 min)
  if (cachedJwt && cachedJwt.expiry > now) {
    return cachedJwt.token;
  }

  const header = { alg: "ES256", kid: config.keyId };
  const claims = { iss: config.teamId, iat: now };

  const encodedHeader = base64url(JSON.stringify(header));
  const encodedClaims = base64url(JSON.stringify(claims));
  const signingInput = `${encodedHeader}.${encodedClaims}`;

  const key = await importPrivateKey(config.privateKey);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput)
  );

  // Convert DER signature to raw r||s format (64 bytes)
  const sigBytes = new Uint8Array(signature);
  let rawSig: Uint8Array;

  if (sigBytes.length === 64) {
    rawSig = sigBytes;
  } else {
    // DER encoded — parse it
    rawSig = derToRaw(sigBytes);
  }

  const token = `${signingInput}.${base64url(rawSig)}`;
  cachedJwt = { token, expiry: now + 3000 }; // Cache for 50 minutes
  return token;
}

function derToRaw(der: Uint8Array): Uint8Array {
  // DER: 0x30 <len> 0x02 <rlen> <r> 0x02 <slen> <s>
  const raw = new Uint8Array(64);
  let offset = 2; // skip 0x30 <len>

  // r
  offset++; // skip 0x02
  const rLen = der[offset++];
  const rStart = rLen > 32 ? offset + (rLen - 32) : offset;
  const rDest = rLen > 32 ? 0 : 32 - rLen;
  raw.set(der.slice(rStart, offset + rLen), rDest);
  offset += rLen;

  // s
  offset++; // skip 0x02
  const sLen = der[offset++];
  const sStart = sLen > 32 ? offset + (sLen - 32) : offset;
  const sDest = sLen > 32 ? 32 : 64 - sLen;
  raw.set(der.slice(sStart, offset + sLen), sDest);

  return raw;
}

export async function sendPush(
  config: APNsConfig,
  options: APNsPushOptions
): Promise<{ ok: boolean; status: number; body: string }> {
  const jwt = await generateJWT(config);
  const host = config.useSandbox
    ? "api.sandbox.push.apple.com"
    : "api.push.apple.com";
  const url = `https://${host}/3/device/${options.token}`;

  const response = await fetch(url, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": options.topic,
      "apns-push-type": options.pushType,
      "apns-priority": String(options.priority ?? 10),
      "content-type": "application/json",
    },
    body: JSON.stringify(options.payload),
  });

  const body = await response.text();
  return { ok: response.ok, status: response.status, body };
}

export type { APNsConfig, APNsPushOptions };
