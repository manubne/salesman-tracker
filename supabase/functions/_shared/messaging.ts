// Shared OTP messaging via MSG91 — WhatsApp primary, SMS fallback.
// Env vars (set with `supabase secrets set`):
//   MSG91_AUTHKEY, MSG91_WA_NUMBER (integrated WhatsApp number),
//   MSG91_WA_TEMPLATE (approved auth template name),
//   MSG91_SMS_TEMPLATE_ID (DLT-approved flow/template id) — optional until DLT ready

const AUTHKEY = Deno.env.get("MSG91_AUTHKEY")!;

export function randomOtp(): string {
  const bytes = new Uint32Array(1);
  crypto.getRandomValues(bytes);
  return String(100000 + (bytes[0] % 900000));
}

function indianMobile(mobile: string): string {
  const digits = mobile.replace(/\D/g, "");
  if (digits.length === 10) return `91${digits}`;
  if (digits.length === 12 && digits.startsWith("91")) return digits;
  throw new Error("invalid Indian mobile number");
}

export async function sendWhatsAppOtp(mobile: string, code: string, salesName: string): Promise<boolean> {
  // MSG91 WhatsApp API: https://docs.msg91.com/whatsapp
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
              to: [indianMobile(mobile)],
            components: {
              // Meta authentication template: body holds ONLY the OTP code,
              // and the "copy code" button repeats the same code. No custom
              // text (e.g. rep name) is permitted in auth templates.
              body_1: { type: "text", value: code },
              button_1: { subtype: "url", type: "text", value: code },
            },
          }],
        },
      },
    }),
  });
  return res.ok;
}

export async function sendSmsOtp(mobile: string, code: string, salesName: string): Promise<boolean> {
  // MSG91 SMS flow API (requires DLT-approved template)
  const res = await fetch("https://control.msg91.com/api/v5/flow/", {
    method: "POST",
    headers: { "Content-Type": "application/json", authkey: AUTHKEY },
    body: JSON.stringify({
      template_id: Deno.env.get("MSG91_SMS_TEMPLATE_ID"),
      recipients: [{ mobiles: indianMobile(mobile), otp: code, name: salesName }],
    }),
  });
  return res.ok;
}

export async function sendOtp(channel: string, mobile: string, code: string, salesName: string) {
  if (channel === "whatsapp") {
    if (await sendWhatsAppOtp(mobile, code, salesName)) return "whatsapp";
    if (Deno.env.get("MSG91_SMS_TEMPLATE_ID") && await sendSmsOtp(mobile, code, salesName)) return "sms"; // fallback
    return null;
  }
  return (await sendSmsOtp(mobile, code, salesName)) ? "sms" : null;
}

export async function sha256(text: string): Promise<string> {
  const data = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
    "Content-Type": "application/json",
  };
}
