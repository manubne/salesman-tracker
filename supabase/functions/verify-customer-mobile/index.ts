// One-time customer mobile verification at creation.
// POST { action: "request", customer_id }  → sends OTP to customer's number
// POST { action: "verify",  customer_id, code } → sets mobile_verified_at
import { createClient } from "npm:@supabase/supabase-js@2";
import { sendOtp, sha256, corsHeaders, randomOtp } from "../_shared/messaging.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders() });
  const headers = corsHeaders();
  try {
    const userClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: req.headers.get("Authorization")! } } },
    );
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401, headers });

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { action, customer_id, code } = await req.json();
    if (typeof customer_id !== "string" || !["request", "verify"].includes(action)) {
      return new Response(JSON.stringify({ error: "invalid request" }), { status: 400, headers });
    }

    const { data: profile } = await admin.from("users").select("name, active").eq("id", user.id).single();
    if (!profile?.active) {
      return new Response(JSON.stringify({ error: "account inactive" }), { status: 403, headers });
    }

    const { data: customer } = await admin.from("customers")
      .select("id, mobile, otp_channel, owner_user_id, mobile_verified_at")
      .eq("id", customer_id).single();
    if (!customer || customer.owner_user_id !== user.id) {
      return new Response(JSON.stringify({ error: "customer not found" }), { status: 404, headers });
    }
    if (customer.mobile_verified_at) {
      return new Response(JSON.stringify({ ok: true, already_verified: true }), { headers });
    }

    // Reuse visit_otps table with a synthetic visit-less row is messy; use a dedicated KV in audit?
    // Simplest: store hash on the customers row via a side table.
    if (action === "request") {
      const { count } = await admin.from("audit_log")
        .select("id", { count: "exact", head: true })
        .eq("action", "customer_otp_requested")
        .eq("entity_id", customer_id)
        .gte("at", new Date(Date.now() - 3600_000).toISOString());
      if ((count ?? 0) >= 3) {
        return new Response(JSON.stringify({ error: "resend limit reached, try later" }), { status: 429, headers });
      }

      const otpCode = randomOtp();
      const channel = await sendOtp(customer.otp_channel, customer.mobile, otpCode, profile?.name ?? "our representative");
      if (!channel) return new Response(JSON.stringify({ error: "delivery failed" }), { status: 502, headers });
      await admin.from("customer_mobile_otps").upsert({
        customer_id,
        otp_hash: await sha256(`${customer_id}:${otpCode}`),
        expires_at: new Date(Date.now() + 10 * 60_000).toISOString(),
        attempts: 0,
      }, { onConflict: "customer_id" });
      await admin.from("audit_log").insert({
        user_id: user.id,
        action: "customer_otp_requested",
        entity: "customer",
        entity_id: customer_id,
        payload: { channel },
      });
      return new Response(JSON.stringify({ ok: true, channel }), { headers });
    }

    if (action === "verify") {
      if (!/^\d{6}$/.test(String(code))) {
        return new Response(JSON.stringify({ error: "invalid code" }), { status: 400, headers });
      }
      const { data: otp } = await admin.from("customer_mobile_otps")
        .select("*").eq("customer_id", customer_id).single();
      if (!otp || new Date(otp.expires_at).getTime() < Date.now()) {
        return new Response(JSON.stringify({ error: "code expired" }), { status: 400, headers });
      }
      if (otp.attempts >= 3) return new Response(JSON.stringify({ error: "too many attempts" }), { status: 429, headers });
      const ok = (await sha256(`${customer_id}:${code}`)) === otp.otp_hash;
      await admin.from("customer_mobile_otps").update({ attempts: otp.attempts + 1 }).eq("customer_id", customer_id);
      if (!ok) return new Response(JSON.stringify({ error: "incorrect code" }), { status: 400, headers });
      await admin.from("customers").update({ mobile_verified_at: new Date().toISOString() }).eq("id", customer_id);
      await admin.from("customer_mobile_otps").delete().eq("customer_id", customer_id);
      return new Response(JSON.stringify({ ok: true }), { headers });
    }

    return new Response(JSON.stringify({ error: "unknown action" }), { status: 400, headers });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers });
  }
});
