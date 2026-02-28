// index.js (FoodTok Worker) — UPDATED to ALSO upsert `places` + `place_stats`
// ✅ After a video is processed, we:
//   1) update the video doc
//   2) upsert places/{placeId}
//   3) upsert place_stats/{placeId}
// This fixes your UI issue where only `videos` gets filled.

import express from "express";
import axios from "axios";
import admin from "firebase-admin";
import fs from "fs";
import path from "path";
import dotenv from "dotenv";
import { exec } from "child_process";
import util from "util";
import { findPlaceGoogle } from "./geocode_google.js";

const execAsync = util.promisify(exec);
dotenv.config({ override: true });

const app = express();
app.use(express.json());

/* ---------- BASIC AUTH FOR RUNONCE ---------- */
function requireWorkerSecret(req, res, next) {
  const secret = req.header("x-worker-secret");

  if (!process.env.WORKER_SECRET) {
    return res
      .status(500)
      .send("WORKER_SECRET not set (check .env and restart terminal)");
  }
  if (secret !== process.env.WORKER_SECRET) {
    return res.status(401).send("Unauthorized (wrong x-worker-secret)");
  }
  next();
}

/* ---------- FIREBASE INIT ---------- */
const serviceAccountPath = "./serviceAccountKey.json";
if (!fs.existsSync(serviceAccountPath)) {
  console.error(`Missing ${serviceAccountPath}. Put it in foodtok-worker folder.`);
  process.exit(1);
}
const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, "utf8"));

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

/* ---------- SMALL HELPERS ---------- */
function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function ensureDir(p) {
  if (!fs.existsSync(p)) fs.mkdirSync(p, { recursive: true });
}

function safeRmDir(p) {
  try {
    fs.rmSync(p, { recursive: true, force: true });
  } catch {}
}

function pickDownloadedVideoFile(dir) {
  const files = fs.readdirSync(dir);
  const preferred = files.find((f) => f.toLowerCase().endsWith(".mp4"));
  if (preferred) return preferred;

  const anyVideo = files.find((f) =>
    [".mkv", ".webm", ".mov", ".mp4"].some((ext) => f.toLowerCase().endsWith(ext))
  );
  return anyVideo || null;
}

function dedupeStrings(arr) {
  return Array.from(
    new Set((arr || []).map((x) => String(x || "").trim()).filter(Boolean))
  );
}

/* ---------- PLACE UPSERT (THIS IS THE IMPORTANT FIX) ---------- */
/**
 * Upserts:
 *  - places/{placeId} : used by Explore map + cards/details
 *  - place_stats/{placeId}
 *
 * NOTE: We intentionally keep doc id = placeId (NOT placeKey) so your Flutter UI
 * continues to work without refactor.
 */
async function upsertPlaceAndStats({ placeId, shopName, address, geo, ai, aiFacts }) {
  if (!placeId) return;

  const placeRef = db.collection("places").doc(placeId);
  const statsRef = db.collection("place_stats").doc(placeId);

  await db.runTransaction(async (tx) => {
    const placeSnap = await tx.get(placeRef);
    const existing = placeSnap.exists ? placeSnap.data() : {};

    const existingTags = Array.isArray(existing?.foodTagsTop) ? existing.foodTagsTop : [];
    const existingPros = Array.isArray(existing?.topPros) ? existing.topPros : [];
    const existingCons = Array.isArray(existing?.topCons) ? existing.topCons : [];

    const newTags = Array.isArray(aiFacts?.foodNames) ? aiFacts.foodNames : [];
    const newPros = Array.isArray(ai?.pros) ? ai.pros : [];
    const newCons = Array.isArray(ai?.cons) ? ai.cons : [];

    const mergedTags = dedupeStrings([...newTags, ...existingTags]).slice(0, 18);
    const mergedPros = dedupeStrings([...newPros, ...existingPros]).slice(0, 8);
    const mergedCons = dedupeStrings([...newCons, ...existingCons]).slice(0, 8);

    const locationGeoPoint = geo ? new admin.firestore.GeoPoint(geo.lat, geo.lon) : null;

    // Place doc: create/merge
    tx.set(
      placeRef,
      {
        name: shopName || existing?.name || placeId,
        addressHint: address || existing?.addressHint || "",
        halalStatus: (ai?.halal || existing?.halalStatus || "unclear"),
        overallSentiment: (existing?.overallSentiment || "mixed"),
        rating: (typeof existing?.rating === "number" ? existing.rating : 0),
        videoCount: admin.firestore.FieldValue.increment(1),
        foodTagsTop: mergedTags,
        topPros: mergedPros,
        topCons: mergedCons,
        lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        // only overwrite if we have geo OR existing is empty
        location: locationGeoPoint ?? (existing?.location ?? null),
      },
      { merge: true }
    );

    // Stats doc: create/merge
    tx.set(
      statsRef,
      {
        placeId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        videoCount: admin.firestore.FieldValue.increment(1),
      },
      { merge: true }
    );
  });
}

/* ---------- JSON HELPERS (EXTRA ROBUST) ---------- */
function stripCodeFences(s) {
  if (!s) return "";
  const m = s.match(/```(?:json)?\s*([\s\S]*?)```/i);
  return (m ? m[1] : s).trim();
}

function smartQuoteToNormal(s) {
  return s.replace(/[\u201C\u201D]/g, '"').replace(/[\u2018\u2019]/g, "'");
}

function removeTrailingCommas(s) {
  return s.replace(/,\s*([}\]])/g, "$1");
}

function extractJSONObjectRegion(s) {
  const raw = stripCodeFences(s);
  const first = raw.indexOf("{");
  const last = raw.lastIndexOf("}");
  if (first === -1 || last === -1 || last <= first) return null;
  return raw.slice(first, last + 1).trim();
}

function tryFixSingleQuotes(jsonish) {
  if (!jsonish) return jsonish;
  let s = jsonish.trim();
  if (!s.startsWith("{") || !s.endsWith("}")) return s;

  s = s.replace(/([{,]\s*)'([^']+?)'\s*:/g, '$1"$2":');
  s = s.replace(/:\s*'([^']*?)'(\s*[},])/g, ':"$1"$2');
  s = s.replace(/\[\s*'([^']*?)'\s*(,|\])/g, '["$1"$2');
  s = s.replace(/,\s*'([^']*?)'\s*(,|\])/g, ',"$1"$2');
  return s;
}

function healTruncatedJson(rawText) {
  if (!rawText) return rawText;
  let s = stripCodeFences(rawText).trim();

  const first = s.indexOf("{");
  if (first === -1) return s;
  s = s.slice(first);

  s = smartQuoteToNormal(s);
  s = removeTrailingCommas(s);

  let inString = false;
  let escape = false;
  let brace = 0;
  let bracket = 0;

  for (let i = 0; i < s.length; i++) {
    const ch = s[i];

    if (escape) {
      escape = false;
      continue;
    }
    if (ch === "\\") {
      if (inString) escape = true;
      continue;
    }
    if (ch === '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;

    if (ch === "{") brace++;
    else if (ch === "}") brace--;
    else if (ch === "[") bracket++;
    else if (ch === "]") bracket--;
  }

  if (inString) s += '"';

  while (bracket > 0) {
    s += "]";
    bracket--;
  }
  while (brace > 0) {
    s += "}";
    brace--;
  }

  s = removeTrailingCommas(s);
  return s.trim();
}

function tryParseJSON(s) {
  if (!s) return null;

  try {
    return JSON.parse(s);
  } catch {}

  const region = extractJSONObjectRegion(s);
  if (region) {
    let cleaned = removeTrailingCommas(smartQuoteToNormal(region));
    try {
      return JSON.parse(cleaned);
    } catch {}
    cleaned = tryFixSingleQuotes(cleaned);
    try {
      return JSON.parse(cleaned);
    } catch {}
  }

  const healed = healTruncatedJson(s);
  if (healed) {
    try {
      return JSON.parse(healed);
    } catch {}
    const region2 = extractJSONObjectRegion(healed);
    if (region2) {
      let cleaned2 = removeTrailingCommas(smartQuoteToNormal(region2));
      try {
        return JSON.parse(cleaned2);
      } catch {}
      cleaned2 = tryFixSingleQuotes(cleaned2);
      try {
        return JSON.parse(cleaned2);
      } catch {}
    }
  }

  return null;
}

/* ---------- AI NORMALIZATION + VALIDATION ---------- */
function normalizeAi(obj) {
  if (!obj || typeof obj !== "object") return null;

  let sentiment = String(obj.sentiment || "").trim().toLowerCase();
  if (!["positive", "neutral", "negative"].includes(sentiment)) sentiment = "neutral";

  let halal = String(obj.halal || "").trim().toLowerCase();
  if (!["halal", "not_halal", "unclear"].includes(halal)) halal = "unclear";

  const pros = Array.isArray(obj.pros)
    ? obj.pros.map((x) => String(x).trim()).filter(Boolean)
    : [];
  const cons = Array.isArray(obj.cons)
    ? obj.cons.map((x) => String(x).trim()).filter(Boolean)
    : [];

  return { sentiment, pros, cons, halal };
}

function isValidAi(obj) {
  if (!obj) return false;
  const okSent = ["positive", "neutral", "negative"].includes(obj.sentiment);
  const okHalal = ["halal", "not_halal", "unclear"].includes(obj.halal);
  const okPros = Array.isArray(obj.pros);
  const okCons = Array.isArray(obj.cons);
  return okSent && okHalal && okPros && okCons;
}

function rebalanceProsCons(ai) {
  if (!ai || typeof ai !== "object") return ai;

  const negWords = [
    "dry","kering","soggy","lembik","masin","terlalu masin","bland","tawar",
    "tak sedap","not","isn't","isnt","kurang","mahal","expensive","overpriced",
    "lambat","slow","burnt","hangit","liat","keras","tak best","not good",
    "not rich","tak rich","tak pekat"
  ];
  const posWords = [
    "sedap","rangup","crispy","juicy","berbaloi","worth","murah","banyak",
    "portion besar","variti","variety","nice","best","padu","lemak","kaw",
    "flavorful","flavourful","garlicky","spicy"
  ];

  const isNeg = (s) => negWords.some((w) => String(s).toLowerCase().includes(w));
  const isPos = (s) => posWords.some((w) => String(s).toLowerCase().includes(w));

  const pros = [];
  const cons = [];

  for (const p of ai.pros || []) {
    if (isNeg(p) && !isPos(p)) cons.push(p);
    else pros.push(p);
  }
  for (const c of ai.cons || []) {
    if (isPos(c) && !isNeg(c)) pros.push(c);
    else cons.push(c);
  }

  const dedupe = (arr) =>
    Array.from(new Set(arr.map((x) => String(x).trim()))).filter(Boolean);

  ai.pros = dedupe(pros).slice(0, 5);
  ai.cons = dedupe(cons).slice(0, 5);

  if (ai.cons.length >= 2 && ai.pros.length === 0) ai.sentiment = "negative";
  if (ai.pros.length >= 2 && ai.cons.length === 0) ai.sentiment = "positive";
  if (ai.pros.length === 0 && ai.cons.length === 0) ai.sentiment = "neutral";

  return ai;
}

/* ---------- OPTION B: DOWNLOAD + AUDIO + TRANSCRIBE ---------- */
async function downloadTikTokToFolder({ url, cwd }) {
  const cmd =
    `py -3.11 -m yt_dlp --no-warnings --restrict-filenames ` +
    `-f "bv*+ba/b" -o "video.%(ext)s" "${url}"`;

  await execAsync(cmd, { cwd, windowsHide: true, maxBuffer: 1024 * 1024 * 20 });

  const file = pickDownloadedVideoFile(cwd);
  if (!file) throw new Error("TikTok download finished but no video file found.");
  return path.join(cwd, file);
}

async function extractAudioWav({ videoPath, cwd }) {
  const out = path.join(cwd, "audio.wav");
  const cmd = `ffmpeg -y -i "${videoPath}" -vn -ac 1 -ar 16000 "${out}"`;
  await execAsync(cmd, { cwd, windowsHide: true, maxBuffer: 1024 * 1024 * 20 });
  if (!fs.existsSync(out)) throw new Error("FFmpeg did not produce audio.wav");
  return out;
}

async function transcribeWithPython({ audioPath, cwd }) {
  const scriptAbs = path.resolve("./transcribe.py");
  if (!fs.existsSync(scriptAbs)) {
    throw new Error("Missing transcribe.py in foodtok-worker folder.");
  }

  const cmd = `py -3.11 "${scriptAbs}" "${audioPath}" --plain`;

  const { stdout } = await execAsync(cmd, {
    cwd,
    windowsHide: true,
    maxBuffer: 1024 * 1024 * 20,
  });

  return String(stdout || "").trim();
}

/* ---------- TRANSCRIPT PREP ---------- */
function cleanTranscriptForLLM(t, maxLen = 6000) {
  if (!t) return "";
  let s = String(t);
  s = s.replace(/\r\n/g, "\n");
  s = s.replace(/[ \t]+/g, " ");
  s = s.replace(/\n{3,}/g, "\n\n");
  if (s.length > maxLen) s = s.slice(0, maxLen);
  return s.trim();
}

function splitToSentences(t) {
  if (!t) return [];
  const raw = t
    .replace(/\r\n/g, "\n")
    .split(/\n+/)
    .flatMap((line) => line.split(/(?<=[.!?])\s+/g));
  return raw.map((x) => x.trim()).filter(Boolean);
}

function extractOpinionSnippets(transcript) {
  const sents = splitToSentences(transcript);
  const kw = [
    "sedap","tak sedap","kering","lembut","rangup","crispy","keras",
    "masin","manis","pedas","lemak","padu","best","terbaik","nice",
    "berbaloi","mahal","murah","harga","portion","banyak","sikit",
    "bau","rasa","tekstur","sos","kuah","sambal","kurang",
    "tasty","dry","crispy","salty","sweet","spicy","worth","price",
    "expensive","cheap","small","big","juicy","bland","overrated",
    "soggy","not","isn't","isnt","garlicky","not rich","premium"
  ];

  const re = new RegExp(
    `\\b(${kw.map((k) => k.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|")})\\b`,
    "i"
  );

  let hits = sents.filter((x) => re.test(x));
  if (hits.length === 0) hits = sents.slice(0, 10);
  return hits.slice(0, 18);
}

function extractPriceHints(transcript) {
  const t = transcript || "";
  const hits = new Set();

  (t.match(/RM\s?\d+(?:\.\d{1,2})?/gi) || []).forEach((x) => hits.add(x.trim()));
  (t.match(/\b\d+(?:\.\d{1,2})?\s*(?:ringgit|rm)\b/gi) || []).forEach((x) => hits.add(x.trim()));

  return Array.from(hits).slice(0, 10);
}

/* ---------- GEMINI CALLS ---------- */
const GEMINI_MODEL = "gemini-2.5-flash";

const structuredSchema = {
  type: "object",
  properties: {
    ai: {
      type: "object",
      properties: {
        sentiment: { type: "string", enum: ["positive", "neutral", "negative"] },
        pros: { type: "array", items: { type: "string" } },
        cons: { type: "array", items: { type: "string" } },
        halal: { type: "string", enum: ["halal", "not_halal", "unclear"] },
      },
      required: ["sentiment", "pros", "cons", "halal"],
    },
    aiFacts: {
      type: "object",
      properties: {
        foodNames: { type: "array", items: { type: "string" } },
        prices: { type: "array", items: { type: "string" } },
        shopName: { type: "string" },
      },
      required: ["foodNames", "prices", "shopName"],
    },
    aiInsights: { type: "array", items: { type: "string" } },
  },
  required: ["ai", "aiFacts"],
};

async function geminiGenerateStructured({ apiKey, prompt, schema, maxTokens }) {
  const endpoint =
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`;

  const resp = await axios.post(
    endpoint,
    {
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: 0.1,
        maxOutputTokens: maxTokens ?? 1536,
        responseMimeType: "application/json",
        responseSchema: schema,
      },
    },
    {
      timeout: 45000,
      validateStatus: (s) => s >= 200 && s < 500,
    }
  );

  if (resp.status >= 400) {
    const msg = resp.data?.error?.message || `Gemini HTTP ${resp.status}`;
    throw new Error(msg);
  }

  const text = resp?.data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  return String(text || "").trim();
}

async function geminiGeneratePlainJSON({ apiKey, prompt, maxTokens }) {
  const endpoint =
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`;

  const resp = await axios.post(
    endpoint,
    {
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: 0.0,
        maxOutputTokens: maxTokens ?? 1024,
        responseMimeType: "application/json",
      },
    },
    {
      timeout: 45000,
      validateStatus: (s) => s >= 200 && s < 500,
    }
  );

  if (resp.status >= 400) {
    const msg = resp.data?.error?.message || `Gemini HTTP ${resp.status}`;
    throw new Error(msg);
  }

  const text = resp?.data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  return String(text || "").trim();
}

function parseStructured(text) {
  const obj = tryParseJSON(text);
  return obj && typeof obj === "object" ? obj : null;
}

function guessShopFromTranscript(t) {
  const s = String(t || "");
  const m1 = s.match(/\b(?:went to|go to|at|from|kat|di)\s+([A-Z][A-Za-z0-9'&.\- ]{2,60})/i);
  if (m1 && m1[1]) return String(m1[1]).trim();
  const m2 = s.match(/\bfrom\s+([A-Z][A-Za-z0-9'&.\- ]{2,60})/i);
  if (m2 && m2[1]) return String(m2[1]).trim();
  return "";
}

/* ---------- MAIN EXTRACTION (RETRY + REPAIR) ---------- */
async function callGeminiExtractAll({ apiKey, video }) {
  const transcriptRaw = (video.transcriptText || "").trim();
  const place = String(video.placeId || "").trim();
  const url = String(video.url || "").trim();

  const transcript = cleanTranscriptForLLM(transcriptRaw, 6000);
  const snippets = extractOpinionSnippets(transcript);
  const prices = extractPriceHints(transcript);

  const basePrompt = `
You extract structured info from a rough TikTok food review transcript (Malay+English mix).
The transcript may contain ASR mistakes. Still infer likely intended meaning.

Return ONLY valid JSON matching schema. No markdown. No extra text.

Rules:
- pros = strictly positive bullet phrases (2–8 words), max 5
- cons = strictly negative bullet phrases (2–8 words), max 5
- If negative wording: soggy/lembik/kering/masin/not rich/overpriced/mahal/kurang => MUST go to cons
- If positive wording: sedap/rangup/crispy/berbaloi/worth/variety/variti => MUST go to pros
- If opinions exist, DO NOT leave both pros and cons empty.
- halal: if not clearly mentioned => "unclear"

- aiFacts is REQUIRED:
  - shopName: The venue/brand name only. NO area words like "SS15", "Kota Damansara", "KL".
    If transcript says "went to X" / "at X" / "kat X" / "di X", extract X.
    If multiple names exist, choose the most likely place name. If unclear: "".
  - foodNames: Specific menu item names (2–6 words each).
  - prices: Extract exact price strings found (prefer "RM18", "18 ringgit"). If none: [].

Context:
placeId: ${place || "unknown"}
url: ${url || "unknown"}
IMPORTANT: placeId is often the area. Use it to disambiguate shop location.

Opinion snippets:
${snippets.map((x, i) => `${i + 1}) ${x}`).join("\n")}

Price hints:
${prices.length ? prices.map((x) => `- ${x}`).join("\n") : "(none)"}

Transcript (shortened):
${transcript || "(empty)"}
`.trim();

  const raw1 = await geminiGenerateStructured({
    apiKey,
    prompt: basePrompt,
    schema: structuredSchema,
    maxTokens: 1536,
  });

  let obj1 = parseStructured(raw1);
  let ai1 = rebalanceProsCons(normalizeAi(obj1?.ai));

  if (obj1 && isValidAi(ai1)) {
    obj1.ai = ai1;
    if (obj1.aiFacts && typeof obj1.aiFacts.shopName === "string") {
      const cur = obj1.aiFacts.shopName.trim();
      if (!cur) {
        const guess = guessShopFromTranscript(transcriptRaw);
        if (guess) obj1.aiFacts.shopName = guess;
      }
    }
    return { ok: true, raw: raw1, obj: obj1, repaired: false };
  }

  await sleep(250);

  const retryPrompt = `
Same task, previous output was invalid/truncated.
Return ONLY valid JSON.
Use ONLY these snippets to extract pros/cons + sentiment + aiFacts.

Opinion snippets:
${snippets.map((x, i) => `${i + 1}) ${x}`).join("\n")}

Price hints:
${prices.length ? prices.map((x) => `- ${x}`).join("\n") : "(none)"}
`.trim();

  const raw2 = await geminiGenerateStructured({
    apiKey,
    prompt: retryPrompt,
    schema: structuredSchema,
    maxTokens: 1536,
  });

  let obj2 = parseStructured(raw2);
  let ai2 = rebalanceProsCons(normalizeAi(obj2?.ai));

  if (obj2 && isValidAi(ai2)) {
    obj2.ai = ai2;
    if (obj2.aiFacts && typeof obj2.aiFacts.shopName === "string") {
      const cur = obj2.aiFacts.shopName.trim();
      if (!cur) {
        const guess = guessShopFromTranscript(transcriptRaw);
        if (guess) obj2.aiFacts.shopName = guess;
      }
    }
    return { ok: true, raw: raw2, obj: obj2, repaired: true, bad: raw1 };
  }

  const bad = raw2 || raw1;
  const repairPrompt = `
You are a JSON repair tool.
Return ONLY valid JSON for this schema:

{
  "ai": {"sentiment":"positive|neutral|negative","pros":[],"cons":[],"halal":"halal|not_halal|unclear"},
  "aiFacts": {"foodNames":[],"prices":[],"shopName":""},
  "aiInsights": []
}

Rules:
- pros/cons arrays of short strings (2–8 words), max 5 each
- halal default "unclear"
- If bad output is truncated, reconstruct the most likely intended values.

Bad output:
${bad}
`.trim();

  const raw3 = await geminiGeneratePlainJSON({
    apiKey,
    prompt: repairPrompt,
    maxTokens: 900,
  });

  const obj3 = parseStructured(raw3);
  const ai3 = rebalanceProsCons(normalizeAi(obj3?.ai));

  if (obj3 && isValidAi(ai3)) {
    obj3.ai = ai3;
    if (obj3.aiFacts && typeof obj3.aiFacts.shopName === "string") {
      const cur = obj3.aiFacts.shopName.trim();
      if (!cur) {
        const guess = guessShopFromTranscript(transcriptRaw);
        if (guess) obj3.aiFacts.shopName = guess;
      }
    }
    return { ok: true, raw: raw3, obj: obj3, repaired: true, bad: bad };
  }

  return {
    ok: false,
    raw: raw3 || raw2 || raw1,
    bad: bad,
    error: "Gemini structured output parse/validation failed",
  };
}

/* ---------- CORE: CLAIM + PROCESS ONE VIDEO ---------- */
async function claimOnePendingVideo() {
  return await db.runTransaction(async (tx) => {
    const snap = await tx.get(
      db.collection("videos").where("status", "==", "pending").limit(1)
    );
    if (snap.empty) return null;

    const doc = snap.docs[0];
    tx.update(doc.ref, {
      status: "processing",
      processingAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { ref: doc.ref, data: doc.data() };
  });
}

async function processClaimedVideo({ claimedRef, data }) {
  let workDir = null;

  try {
    if (!process.env.GEMINI_API_KEY) {
      throw new Error("GEMINI_API_KEY not set in .env");
    }

    if (!data?.url || typeof data.url !== "string") {
      await claimedRef.update({
        status: "error",
        error: "Missing or invalid url field in Firestore doc",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return { ok: false, message: "Bad Firestore doc (missing url). Marked error." };
    }

    console.log("Processing:", data.url);

    const docId = claimedRef.id;
    workDir = path.join(process.cwd(), "tmp", docId);
    ensureDir(workDir);

    // Reuse transcript if exists
    let transcript = String(data.transcriptText || "").trim();
    if (!transcript || transcript.length < 8) {
      const videoPath = await downloadTikTokToFolder({ url: data.url, cwd: workDir });
      const audioPath = await extractAudioWav({ videoPath, cwd: workDir });
      transcript = await transcribeWithPython({ audioPath, cwd: workDir });

      await claimedRef.update({
        transcriptText: transcript,
        transcriptUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    const enrichedVideo = { ...data, transcriptText: transcript };

    const result = await callGeminiExtractAll({
      apiKey: process.env.GEMINI_API_KEY,
      video: enrichedVideo,
    });

    const debugBase = {
      aiRaw: result.raw || "",
      aiRepaired: !!result.repaired,
      aiBadRaw: result.bad || null,
      aiUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const placeId = String(data.placeId || "").trim();

    // manual user inputs (from SubmitScreen)
    const userShopName = typeof data.userShopName === "string" ? data.userShopName.trim() : "";
    const userAddress = typeof data.userAddress === "string" ? data.userAddress.trim() : "";

    if (!result.ok) {
      const safeAi = { sentiment: "neutral", pros: [], cons: [], halal: "unclear" };
      const safeFacts = { foodNames: [], prices: [], shopName: userShopName || "" };

      await claimedRef.update({
        status: "processed",
        ...debugBase,
        ai: safeAi,
        aiFacts: safeFacts,
        aiInsights: [],
        error: result.error || "Gemini failed; stored defaults",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // ✅ STILL create/update places + stats so your UI is not empty
      await upsertPlaceAndStats({
        placeId,
        shopName: userShopName || placeId,
        address: userAddress,
        geo: null,
        ai: safeAi,
        aiFacts: safeFacts,
      });

      return { ok: true, message: `Processed with defaults (Gemini failed): ${result.error}` };
    }

    const aiFinal = rebalanceProsCons(normalizeAi(result.obj.ai));
    const aiFacts = result.obj.aiFacts || { foodNames: [], prices: [], shopName: "" };
    const aiInsights = Array.isArray(result.obj.aiInsights) ? result.obj.aiInsights : [];

    // ✅ Always safe defaults (avoid "Cannot read properties of undefined (foodNames)")
    const safeFacts = {
      foodNames: Array.isArray(aiFacts.foodNames) ? aiFacts.foodNames.slice(0, 8) : [],
      prices: Array.isArray(aiFacts.prices) ? aiFacts.prices.slice(0, 10) : [],
      shopName:
        userShopName ||
        (typeof aiFacts.shopName === "string" ? aiFacts.shopName.trim() : ""),
    };

    // ✅ Geocode (Google)
    let geo = null;
    try {
      const shopFromAi = typeof safeFacts.shopName === "string" ? safeFacts.shopName.trim() : "";
      const shop = userShopName || shopFromAi;
      const area = placeId;

      if (shop) {
        geo = await findPlaceGoogle({
          shopName: shop,
          address: userAddress,
          area,
        });
      }
    } catch (e) {
      console.log("Geocode failed:", e?.message || String(e));
    }

    await claimedRef.update({
      status: "processed",
      ...debugBase,
      ai: isValidAi(aiFinal)
        ? aiFinal
        : { sentiment: "neutral", pros: [], cons: [], halal: "unclear" },
      aiFacts: safeFacts,
      location: geo
        ? {
            lat: geo.lat,
            lon: geo.lon,
            name: geo.name || safeFacts.shopName || placeId,
            source: geo.source || "google",
          }
        : null,
      aiInsights: aiInsights.map((x) => String(x).trim()).filter(Boolean).slice(0, 6),
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
      error: admin.firestore.FieldValue.delete(),
    });

    // ✅ THIS IS THE KEY: keep `places` + `place_stats` in sync with the new processed video
    await upsertPlaceAndStats({
      placeId,
      shopName: safeFacts.shopName || placeId,
      address: userAddress,
      geo,
      ai: aiFinal,
      aiFacts: safeFacts,
    });

    return { ok: true, message: "Processed 1 video + updated places/place_stats ✅" };
  } catch (err) {
    console.error("Worker error:", err?.message || err);

    // Put it back to pending so it can retry later
    try {
      await claimedRef.update({
        status: "pending",
        error: String(err?.message || err),
      });
    } catch {}

    return { ok: false, message: "Worker error" };
  } finally {
    if (workDir) safeRmDir(workDir);
  }
}

/* ---------- HEALTH CHECK ---------- */
app.get("/healthz", (req, res) => {
  res.send("FoodTok Worker Alive");
});

/* ---------- RUN ONCE (MANUAL) ---------- */
app.post("/runOnce", requireWorkerSecret, async (req, res) => {
  try {
    const claimed = await claimOnePendingVideo();
    if (!claimed) return res.send("No pending videos");

    const out = await processClaimedVideo({ claimedRef: claimed.ref, data: claimed.data });
    return res.status(out.ok ? 200 : 500).send(out.message);
  } catch (e) {
    console.error("runOnce error:", e?.message || e);
    return res.status(500).send("Worker error");
  }
});

/* ---------- AUTO POLL (AUTOMATIC) ---------- */
let _polling = false;

async function pollLoop() {
  if (_polling) return;
  _polling = true;

  const interval = Number(process.env.POLL_INTERVAL_MS || "4000");
  console.log(`[AUTO_POLL] enabled. interval=${interval}ms`);

  while (true) {
    try {
      const claimed = await claimOnePendingVideo();
      if (!claimed) {
        await sleep(interval);
        continue;
      }

      const out = await processClaimedVideo({ claimedRef: claimed.ref, data: claimed.data });
      console.log("[AUTO_POLL]", out.ok ? "OK" : "FAIL", out.message);

      // small pause so we don’t hammer APIs
      await sleep(300);
    } catch (e) {
      console.log("[AUTO_POLL] loop error:", e?.message || String(e));
      await sleep(interval);
    }
  }
}

/* ---------- START SERVER ---------- */
const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log("Worker running on", PORT);

  const auto = String(process.env.AUTO_POLL || "").toLowerCase();
  if (auto === "true" || auto === "1" || auto === "yes") {
    pollLoop(); // ✅ starts automatic processing
  } else {
    console.log("[AUTO_POLL] disabled. Use /runOnce to process manually.");
  }
});