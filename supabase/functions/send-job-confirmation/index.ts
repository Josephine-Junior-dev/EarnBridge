import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405, headers: cors });

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const resendKey = Deno.env.get("RESEND_API_KEY");
    const siteUrl = Deno.env.get("EARNBRIDGE_SITE_URL");
    const from = Deno.env.get("EMAIL_FROM");

    if (!resendKey || !siteUrl || !from) {
      return new Response(JSON.stringify({ error: "Email delivery is not configured. Set RESEND_API_KEY, EARNBRIDGE_SITE_URL and EMAIL_FROM." }), {
        status: 503, headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const authHeader = req.headers.get("Authorization") || "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) return new Response(JSON.stringify({ error: "Sign-in required." }), { status: 401, headers: { ...cors, "Content-Type": "application/json" } });

    const userClient = createClient(url, anonKey, { global: { headers: { Authorization: `Bearer ${jwt}` } } });
    const { data: authData, error: authError } = await userClient.auth.getUser(jwt);
    if (authError || !authData.user) return new Response(JSON.stringify({ error: "Your session could not be verified." }), { status: 401, headers: { ...cors, "Content-Type": "application/json" } });

    const body = await req.json();
    const recordId = String(body.record_id || "");
    if (!recordId) return new Response(JSON.stringify({ error: "record_id is required." }), { status: 400, headers: { ...cors, "Content-Type": "application/json" } });

    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: record, error: recordError } = await admin.from("eb_work_records")
      .select("id,owner_id,client_email,project_title,status")
      .eq("id", recordId).eq("owner_id", authData.user.id).maybeSingle();
    if (recordError) throw recordError;
    if (!record) return new Response(JSON.stringify({ error: "Work record not found or not owned by this account." }), { status: 404, headers: { ...cors, "Content-Type": "application/json" } });
    if (!record.client_email) return new Response(JSON.stringify({ error: "Add the customer's email address before requesting confirmation." }), { status: 400, headers: { ...cors, "Content-Type": "application/json" } });
    if (record.status === "verified" || record.status === "disputed") return new Response(JSON.stringify({ error: "This record is not eligible for another confirmation request." }), { status: 409, headers: { ...cors, "Content-Type": "application/json" } });

    const { data: issued, error: issueError } = await admin.rpc("eb_issue_work_confirmation", { p_record_id: recordId }).single();
    if (issueError) throw issueError;

    const confirmUrl = `${siteUrl.replace(/\/$/, "")}/confirm.html?token=${encodeURIComponent(issued.token)}`;
    const safeTitle = String(record.project_title).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
    const emailResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from,
        to: [issued.customer_email],
        subject: "Please confirm completed work on EarnBridge",
        html: `<div style="font-family:Arial,sans-serif;max-width:560px;margin:auto;color:#17362a"><h2>Work confirmation request</h2><p>A service provider has asked you to confirm whether they completed this work:</p><div style="padding:18px;background:#f2f8f4;border-radius:12px"><strong>${safeTitle}</strong></div><p>Please review the request and choose whether to confirm or reject it. Your response will be recorded in an audit trail.</p><p><a href="${confirmUrl}" style="display:inline-block;background:#087f5b;color:white;text-decoration:none;padding:13px 20px;border-radius:8px">Review and respond</a></p><p style="font-size:12px;color:#718078">This link is private, single-use and expires in seven days. If you did not work with this provider, reject the request or ignore this email.</p></div>`,
      }),
    });
    if (!emailResponse.ok) {
      const details = await emailResponse.text();
      throw new Error(`Email provider error: ${details.slice(0, 300)}`);
    }

    return new Response(JSON.stringify({ success: true, message: "Confirmation request sent to the customer email address." }), {
      status: 200, headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("send-job-confirmation:", error);
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : "Unexpected server error." }), {
      status: 400, headers: { ...cors, "Content-Type": "application/json" },
    });
  }
});
