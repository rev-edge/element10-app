// Element 10 — normalize-checklist Edge Function (first backend/LLM path).
//
// Purpose: map an arbitrary trading-card checklist (Topps/Beckett/Pokémon exports) to the app's
// canonical card schema using an LLM, from a SMALL SAMPLE of rows. The client then applies the
// returned mapping to ALL rows deterministically, so the LLM cost is one small call per import.
//
// Security:
//  - verify_jwt is enabled at the gateway (deploy flag) AND we re-verify inside: getUser() must
//    return a real authenticated user, else 401. Anon callers are rejected.
//  - ANTHROPIC_API_KEY is read from Deno.env (a Supabase secret). It never leaves the server.
//    If it is not set, we return {ok:false, code:"not_configured"} so the client falls back to
//    Direct import gracefully.
//  - Input is capped (columns, sample rows, total chars) to bound cost/abuse.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}

const MAX_COLS = 80;
const MAX_SAMPLE_ROWS = 30;
const MAX_CHARS = 24000;

const INSTRUCTIONS =
`You are given the HEADERS and a SAMPLE of rows from a trading-card checklist export (Topps, Beckett, Pokemon, sports, etc.). Infer how to map its columns to a fixed schema and how to derive card hierarchy (base vs parallel vs insert).

Canonical card fields:
- num: the card number / identifier (e.g. "199/191", "TG12", "006")
- name: the player / character / card name
- set: the set or product name
- rarity: rarity text (e.g. "Common", "SIR", "Refractor")
- value: market / book price as a number
- parallel: the parallel / variation / finish name (e.g. "Base", "Silver", "Gold", "Refractor", "Holo"). Empty for plain base cards.
- cardType: one of base | parallel | insert

Return ONLY this JSON object, no prose, no markdown fences:
{
 "columnMapping": { "<each source header>": "num|name|set|rarity|value|parallel|cardType|ignore" },
 "cardTypeValues": { "<raw value seen in the cardType column>": "base|parallel|insert" },
 "parallelColumn": "<source header holding the parallel/variation name, or null>",
 "insertKeywords": ["lowercase substrings in name/rarity that indicate an INSERT"],
 "parallelKeywords": ["lowercase substrings that indicate a PARALLEL when there is no explicit parallel column"],
 "setName": "<best single set / product name for the whole file>",
 "confidence": "high|medium|low",
 "notes": "<one or two short sentences: how you mapped columns and how hierarchy is derived>",
 "unmapped": ["<source headers you could not confidently map>"]
}
Rules:
- Map EVERY source header. Use "ignore" for headers with no canonical fit and also list them in "unmapped".
- At most ONE source header per canonical field (pick the best); map extra similar columns to "ignore".
- Include "cardTypeValues" ONLY if a header maps to cardType; otherwise return {}.
- If there is no explicit parallel/variation column, set "parallelColumn" to null and rely on "parallelKeywords".
- Base cards: cardType "base", parallel "". Be conservative: when unsure prefer "base" and lower the confidence.`;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, code: "method", message: "POST only." }, 405);

  // ---- auth: require a real authenticated user (reject anon) ----
  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) return json({ ok: false, code: "unauthorized", message: "Sign in required." }, 401);
  const SB_URL = Deno.env.get("SUPABASE_URL") || "";
  const ANON = Deno.env.get("SUPABASE_ANON_KEY") || "";
  try {
    const authed = createClient(SB_URL, ANON, { global: { headers: { Authorization: `Bearer ${token}` } } });
    const { data: { user }, error: uErr } = await authed.auth.getUser();
    if (uErr || !user) return json({ ok: false, code: "unauthorized", message: "Sign in required." }, 401);
  } catch (_e) {
    return json({ ok: false, code: "unauthorized", message: "Sign in required." }, 401);
  }

  // ---- parse + cap input ----
  let body: any;
  try { body = await req.json(); } catch { return json({ ok: false, code: "bad_request", message: "Invalid JSON body." }, 400); }
  const headers = Array.isArray(body?.headers) ? body.headers.map((h: any) => ("" + (h ?? "")).slice(0, 120)) : null;
  let rows = Array.isArray(body?.sampleRows) ? body.sampleRows : null;
  if (!headers || !rows) return json({ ok: false, code: "bad_request", message: "Expected { headers:[], sampleRows:[[]] }." }, 400);
  if (headers.length > MAX_COLS) return json({ ok: false, code: "too_large", message: `Too many columns (max ${MAX_COLS}).` }, 413);
  rows = rows.slice(0, MAX_SAMPLE_ROWS).map((r: any) => Array.isArray(r) ? r.slice(0, MAX_COLS).map((c: any) => ("" + (c ?? "")).slice(0, 200)) : []);
  const sample = { headers, rows };
  if (JSON.stringify(sample).length > MAX_CHARS) return json({ ok: false, code: "too_large", message: "Sample payload too large." }, 413);

  // ---- key (server-side secret) ----
  const KEY = Deno.env.get("ANTHROPIC_API_KEY");
  if (!KEY) return json({ ok: false, code: "not_configured", message: "Smart import is not configured yet (ANTHROPIC_API_KEY is not set). Use Direct import, or ask the admin to add the key." });

  // ---- one bounded LLM call on the sample ----
  const anthReq = {
    model: "claude-haiku-4-5",
    max_tokens: 1200,
    system: "You map trading-card checklist spreadsheets to a fixed schema. Reply with ONLY a JSON object.",
    messages: [{ role: "user", content: INSTRUCTIONS + "\n\nDATA:\n" + JSON.stringify(sample) }],
  };
  let aRes: Response;
  try {
    aRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": KEY, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify(anthReq),
    });
  } catch (_e) {
    return json({ ok: false, code: "upstream", message: "Could not reach the model." }, 502);
  }
  if (!aRes.ok) {
    const t = await aRes.text().catch(() => "");
    return json({ ok: false, code: "upstream", message: "Model error (" + aRes.status + ").", detail: t.slice(0, 300) }, 502);
  }
  const aJson: any = await aRes.json().catch(() => null);
  const text = ((aJson?.content) || []).map((b: any) => b?.text || "").join("").trim();
  let mapping: any = null;
  try { mapping = JSON.parse(text); }
  catch { const m = text.match(/\{[\s\S]*\}/); if (m) { try { mapping = JSON.parse(m[0]); } catch { /* ignore */ } } }
  if (!mapping || typeof mapping !== "object" || typeof mapping.columnMapping !== "object" || !mapping.columnMapping) {
    return json({ ok: false, code: "parse", message: "The model returned output that could not be used. Try Direct import." });
  }
  return json({ ok: true, mapping, usage: aJson?.usage || null });
});
