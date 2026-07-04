// ════════════════════════════════════════════════════════════════════════════
//  Edge Function: send-registration-otp
//  Triggered by a Database Webhook on INSERT into `company_registration`.
//  Pushes the OTP to every owner / super-admin device via FCM HTTP v1.
//
//  Secrets required (supabase secrets set ...):
//    SUPABASE_URL                (auto-injected)
//    SUPABASE_SERVICE_ROLE_KEY   (auto-injected)
//    FIREBASE_PROJECT_ID
//    FIREBASE_CLIENT_EMAIL
//    FIREBASE_PRIVATE_KEY        (with literal \n escapes)
// ════════════════════════════════════════════════════════════════════════════
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const FIREBASE_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID")!;
const FIREBASE_CLIENT_EMAIL = Deno.env.get("FIREBASE_CLIENT_EMAIL")!;
const FIREBASE_PRIVATE_KEY = (Deno.env.get("FIREBASE_PRIVATE_KEY") ?? "").replace(
  /\\n/g,
  "\n",
);

// ─── Mint an OAuth2 access token for the FCM HTTP v1 API ─────────────────────
function pemToBinary(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const raw = atob(body);
  const buf = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) buf[i] = raw.charCodeAt(i);
  return buf.buffer;
}

function b64url(input: string | Uint8Array): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let str = "";
  for (const b of bytes) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claim = {
    iss: FIREBASE_CLIENT_EMAIL,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claim))}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToBinary(FIREBASE_PRIVATE_KEY),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)),
  );
  const jwt = `${unsigned}.${b64url(sig)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const json = await res.json();
  if (!json.access_token) throw new Error(`OAuth failed: ${JSON.stringify(json)}`);
  return json.access_token as string;
}

async function sendToToken(accessToken: string, token: string, otp: string, company: string) {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: {
            title: "New company registration",
            body: `${company} requested access. Approval OTP: ${otp}`,
          },
          data: { type: "company_registration_otp", otp, company },
          android: {
            priority: "HIGH",
            notification: { channel_id: "company_registration", sound: "default" },
          },
        },
      }),
    },
  );
  return { token, status: res.status, body: await res.text() };
}

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    // Database Webhook delivers the inserted row under `record`.
    const record = payload.record ?? payload;
    const otp: string = record.otp_code;
    const company: string = record.company_name ?? "A new company";
    if (!otp) return new Response("no otp in payload", { status: 400 });

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data: devices, error } = await supabase
      .from("super_admin_devices")
      .select("fcm_token");
    if (error) throw error;
    if (!devices || devices.length === 0) {
      return new Response(JSON.stringify({ sent: 0, note: "no super-admin devices" }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    const accessToken = await getAccessToken();
    const results = await Promise.all(
      devices.map((d) => sendToToken(accessToken, d.fcm_token, otp, company)),
    );

    // Remove tokens FCM reports as dead (UNREGISTERED / invalid) so they stop
    // polluting future sends.
    const dead = results
      .filter((r) => r.status === 404 || r.status === 400)
      .map((r) => r.token);
    if (dead.length > 0) {
      await supabase.from("super_admin_devices").delete().in("fcm_token", dead);
    }

    const delivered = results.filter((r) => r.status === 200).length;
    return new Response(
      JSON.stringify({ sent: results.length, delivered, pruned: dead.length, results }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
