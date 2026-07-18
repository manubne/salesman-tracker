// POST { visit_id, lat, lng, accuracy_m, mock_location }
// Generates OTP, sends to the CUSTOMER's phone, stores hash.
import { createClient } from "npm:@supabase/supabase-js@2";
import { sendOtp, sha256, corsHeaders, randomOtp } from "../_shared/messaging.ts";

const OTP_TTL_MIN = 10;
const MAX_RESENDS = 3;
const VERIFY_WINDOW_BEFORE_H = 1;
const VERIFY_WINDOW_AFTER_H = 4;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders() });
  const headers = corsHeaders();
  try {
    const authHeader = req.headers.get("Authorization")!;
    // Client-scoped: identifies the calling sales person
    const userClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401, headers });

    // Service role for privileged writes
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const { visit_id, lat, lng, accuracy_m, mock_location } = await req.json();
    if (typeof visit_id !== "string" || typeof lat !== "number" || lat < -90 || lat > 90 ||
        typeof lng !== "number" || lng < -180 || lng > 180 ||
        typeof accuracy_m !== "number" || accuracy_m < 0 || typeof mock_location !== "boolean") {
      return new Response(JSON.stringify({ error: "invalid request" }), { status: 400, headers });
    }

    const { data: visit } = await admin
      .from("visits")
      .select("id, user_id, scheduled_at, status, customers(id, mobile, otp_channel, name)")
      .eq("id", visit_id).single();
    if (!visit || visit.user_id !== user.id) {
      return new Response(JSON.stringify({ error: "visit not found" }), { status: 404, headers });
    }
    if (visit.status !== "planned") {
      return new Response(JSON.stringify({ error: "visit is not in planned state" }), { status: 400, headers });
    }

    // Time window check (server time)
    const sched = new Date(visit.scheduled_at).getTime();
    const now = Date.now();
    if (now < sched - VERIFY_WINDOW_BEFORE_H * 3600_000 || now > sched + VERIFY_WINDOW_AFTER_H * 3600_000) {
      return new Response(JSON.stringify({ error: "outside verification window" }), { status: 400, headers });
    }

    // Resend limit
    const { count } = await admin.from("visit_otps")
      .select("id", { count: "exact", head: true })
      .eq("visit_id", visit_id)
      .gte("created_at", new Date(now - 3600_000).toISOString());
    if ((count ?? 0) >= MAX_RESENDS) {
      return new Response(JSON.stringify({ error: "resend limit reached, try later" }), { status: 429, headers });
    }

    const { data: profile } = await admin.from("users").select("name, active").eq("id", user.id).single();
    if (!profile?.active) {
      return new Response(JSON.stringify({ error: "account inactive" }), { status: 403, headers });
    }
    const customer = (visit as any).customers;

    const code = randomOtp();
    const channelUsed = await sendOtp(customer.otp_channel, customer.mobile, code, profile?.name ?? "our representative");
    if (!channelUsed) {
      return new Response(JSON.stringify({ error: "message delivery failed" }), { status: 502, headers });
    }

    const { error: otpError } = await admin.from("visit_otps").insert({
      visit_id,
      otp_hash: await sha256(`${visit_id}:${code}`),
      channel: channelUsed,
      sent_to_mobile: customer.mobile,
      expires_at: new Date(now + OTP_TTL_MIN * 60_000).toISOString(),
    });
    if (otpError) throw otpError;

    // Record the GPS fix taken at request time (flags applied at verify)
    const { error: auditError } = await admin.from("audit_log").insert({
      user_id: user.id, action: "otp_requested", entity: "visit", entity_id: visit_id,
      payload: { lat, lng, accuracy_m, mock_location, channel: channelUsed },
    });
    if (auditError) throw auditError;

    return new Response(JSON.stringify({ ok: true, channel: channelUsed, expires_in_min: OTP_TTL_MIN }), { headers });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers });
  }
});
