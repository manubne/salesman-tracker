// POST { visit_id, code, lat, lng, accuracy_m, mock_location }
// Verifies OTP, computes distance from customer pin, sets flags, marks visit verified.
import { createClient } from "npm:@supabase/supabase-js@2";
import { sha256, corsHeaders } from "../_shared/messaging.ts";

const MAX_ATTEMPTS = 3;
const FLAG_DISTANCE_M = 300;
const FLAG_ACCURACY_M = 50;

function distanceM(lat1: number, lng1: number, lat2: number, lng2: number) {
  const r = (d: number) => (d * Math.PI) / 180;
  return 6371000 * 2 * Math.asin(Math.sqrt(
    Math.sin(r(lat2 - lat1) / 2) ** 2 +
    Math.cos(r(lat1)) * Math.cos(r(lat2)) * Math.sin(r(lng2 - lng1) / 2) ** 2,
  ));
}

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
    const { visit_id, code, lat, lng, accuracy_m, mock_location } = await req.json();
    if (typeof visit_id !== "string" || !/^\d{6}$/.test(String(code)) ||
        typeof lat !== "number" || lat < -90 || lat > 90 ||
        typeof lng !== "number" || lng < -180 || lng > 180 ||
        typeof accuracy_m !== "number" || accuracy_m < 0 || typeof mock_location !== "boolean") {
      return new Response(JSON.stringify({ error: "invalid request" }), { status: 400, headers });
    }

    const { data: profile } = await admin.from("users").select("active").eq("id", user.id).single();
    if (!profile?.active) {
      return new Response(JSON.stringify({ error: "account inactive" }), { status: 403, headers });
    }

    const { data: visit } = await admin
      .from("visits")
      .select("id, user_id, status, customers(id, lat, lng)")
      .eq("id", visit_id).single();
    if (!visit || visit.user_id !== user.id) {
      return new Response(JSON.stringify({ error: "visit not found" }), { status: 404, headers });
    }
    if (visit.status !== "planned") {
      return new Response(JSON.stringify({ error: "visit is not in planned state" }), { status: 400, headers });
    }

    // Latest unexpired, unverified OTP
    const { data: otp } = await admin.from("visit_otps")
      .select("*").eq("visit_id", visit_id).is("verified_at", null)
      .order("created_at", { ascending: false }).limit(1).single();
    if (!otp || new Date(otp.expires_at).getTime() < Date.now()) {
      return new Response(JSON.stringify({ error: "code expired, request a new one" }), { status: 400, headers });
    }
    if (otp.attempts >= MAX_ATTEMPTS) {
      return new Response(JSON.stringify({ error: "too many attempts" }), { status: 429, headers });
    }

    const ok = (await sha256(`${visit_id}:${code}`)) === otp.otp_hash;
    const { error: attemptError } = await admin.from("visit_otps").update({
      attempts: otp.attempts + 1,
      verified_at: ok ? new Date().toISOString() : null,
    }).eq("id", otp.id);
    if (attemptError) throw attemptError;
    if (!ok) {
      return new Response(JSON.stringify({ error: "incorrect code", attempts_left: MAX_ATTEMPTS - otp.attempts - 1 }), { status: 400, headers });
    }

    // Flags
    const customer = (visit as any).customers;
    const flags: string[] = [];
    let distance: number | null = null;
    if (customer.lat != null && customer.lng != null) {
      distance = distanceM(lat, lng, customer.lat, customer.lng);
      if (distance > FLAG_DISTANCE_M) flags.push("far_from_pin");
    }
    if (mock_location) flags.push("mock_location");
    if (accuracy_m > FLAG_ACCURACY_M) flags.push("low_accuracy");

    const { error: visitError } = await admin.from("visits").update({
      status: "verified",
      verified_at: new Date().toISOString(),
      verified_lat: lat,
      verified_lng: lng,
      gps_accuracy_m: accuracy_m,
      distance_from_pin_m: distance,
      flags,
    }).eq("id", visit_id);
    if (visitError) throw visitError;

    // First verified visit pins the customer location
    if (customer.lat == null && !mock_location && accuracy_m <= FLAG_ACCURACY_M) {
      const { error: pinError } = await admin.from("customers").update({ lat, lng }).eq("id", customer.id);
      if (pinError) throw pinError;
    }

    const { error: auditError } = await admin.from("audit_log").insert({
      user_id: user.id, action: "visit_verified", entity: "visit", entity_id: visit_id,
      payload: { lat, lng, accuracy_m, mock_location, distance, flags },
    });
    if (auditError) throw auditError;

    return new Response(JSON.stringify({ ok: true, flags, distance_m: distance }), { headers });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers });
  }
});
