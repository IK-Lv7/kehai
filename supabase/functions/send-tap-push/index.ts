// taps への INSERT をきっかけに、受け取る側の端末へ APNs でトントンの通知を送る。
// 呼び出し元は notify_tap() トリガー。合言葉 (x-webhook-secret) が合わないものは受け付けない。
//
// 必要な Secrets:
//   PUSH_WEBHOOK_SECRET  Vault の push_webhook_secret と同じ値
//   APNS_KEY_P8          APNs 認証キー (.p8) の中身
//   APNS_KEY_ID          そのキーの ID
//   APNS_TEAM_ID         Apple Developer の Team ID
//   APNS_TOPIC           アプリの Bundle ID (com.hinodeentertainment.kehai)

import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const APNS_HOSTS = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
} as const;

// APNs の認証トークンは、20分〜1時間の間で使い回す。
let cachedJwt: { token: string; issuedAt: number } | null = null;

async function apnsJwt(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && now - cachedJwt.issuedAt < 40 * 60) return cachedJwt.token;
  const key = await importPKCS8(Deno.env.get("APNS_KEY_P8")!.replace(/\\n/g, "\n"), "ES256");
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: Deno.env.get("APNS_KEY_ID")! })
    .setIssuer(Deno.env.get("APNS_TEAM_ID")!)
    .setIssuedAt(now)
    .sign(key);
  cachedJwt = { token, issuedAt: now };
  return token;
}

Deno.serve(async (req) => {
  if (req.headers.get("x-webhook-secret") !== Deno.env.get("PUSH_WEBHOOK_SECRET")) {
    return new Response("unauthorized", { status: 401 });
  }

  const { sender_id, receiver_id } = await req.json();
  if (!sender_id || !receiver_id) return new Response("bad request", { status: 400 });

  // 受け取りをオフにしている人には送らない。
  const { data: receiver } = await supabase
    .from("profiles").select("receive_taps").eq("id", receiver_id).single();
  if (!receiver?.receive_taps) return new Response("muted");

  const { data: sender } = await supabase
    .from("profiles").select("display_name").eq("id", sender_id).single();
  const { data: tokens } = await supabase
    .from("device_tokens").select("token, environment").eq("user_id", receiver_id);
  if (!tokens?.length) return new Response("no device");

  const body = JSON.stringify({
    aps: {
      alert: { title: sender?.display_name || "Kehai", body: "トントン" },
      sound: "default",
      // アプリが裏で起きられたら、ウィジェットのキャラを手を振る絵にする。
      "content-available": 1,
    },
    sender_id,
  });
  const jwt = await apnsJwt();

  await Promise.all(tokens.map(async ({ token, environment }) => {
    const res = await fetch(`${APNS_HOSTS[environment as keyof typeof APNS_HOSTS]}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": Deno.env.get("APNS_TOPIC")!,
        "apns-push-type": "alert",
        "apns-priority": "10",
        // 連打されても、通知センターには1つにまとめる。
        "apns-collapse-id": `tap-${sender_id}`,
      },
      body,
    });
    if (res.status === 410 || res.status === 400) {
      const reason = (await res.json().catch(() => ({})))?.reason;
      // 使えなくなったトークン (アプリを消した・環境違い) は捨てる。
      if (res.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered") {
        await supabase.from("device_tokens").delete().eq("token", token);
      }
    }
  }));

  return new Response("ok");
});
