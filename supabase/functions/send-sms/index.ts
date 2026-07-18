// Supabase Auth "Send SMS" hook.
// Delivers the LOGIN OTP to the sales person's own phone via MSG91 WhatsApp
// (same approved authentication template used for visit OTPs).
// JWT verification is disabled for this function; the Supabase Auth Hook is
// authenticated with its Standard Webhooks signature.
import { Webhook } from "npm:standardwebhooks@1.0.0";

const AUTHKEY = Deno.env.get("MSG91_AUTHKEY")!;
const HOOK_SECRET = Deno.env.get("SEND_SMS_HOOK_SECRET") ?? "";

function errorResponse(status: number, message: string) {
  return new Response(
    JSON.stringify({ error: { http_code: status, message } }),
    { status, headers: { "Content-Type": "application/json" } },
  );
}

Deno.serve(async (req) => {
  const raw = await req.text();
  if (!HOOK_SECRET) {
    return errorResponse(503, "hook secret not configured");
  }

  let payload: any;
  try {
    const secret = HOOK_SECRET.replace(/^v1,whsec_/, "");
    payload = new Webhook(secret).verify(raw, Object.fromEntries(req.headers));
  } catch (_) {
    return errorResponse(401, "invalid hook signature");
  }

  let phone = "";
  let otp = "";
  try {
    phone = String(payload.user?.phone ?? "").replace(/[^0-9]/g, "");
    otp = String(payload.sms?.otp ?? "");
  } catch (_) {
    return errorResponse(400, "invalid hook payload");
  }
  if (!phone || !otp) {
    return errorResponse(400, "missing phone or otp");
  }
  const res = await fetch("https://control.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/bulk/", {
    method: "POST",
    headers: { "Content-Type": "application/json", authkey: AUTHKEY },
    body: JSON.stringify({
      integrated_number: Deno.env.get("MSG91_WA_NUMBER"),
      content_type: "template",
      payload: {
        messaging_product: "whatsapp",
        type: "template",
        template: {
          name: Deno.env.get("MSG91_WA_TEMPLATE"),
          language: { code: "en", policy: "deterministic" },
          namespace: null,
          to_and_components: [{
            to: [phone],
            components: {
              body_1: { type: "text", value: otp },
              button_1: { subtype: "url", type: "text", value: otp },
            },
          }],
        },
      },
    }),
  });
  if (!res.ok) {
    const t = await res.text();
    console.error("MSG91 delivery failed", res.status, t);
    return errorResponse(502, "OTP delivery failed");
  }
  return new Response(JSON.stringify({}), { status: 200, headers: { "Content-Type": "application/json" } });
});
