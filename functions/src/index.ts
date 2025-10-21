import * as functions from "firebase-functions/v1"; // 1st-gen (Spark-friendly)
import * as admin from "firebase-admin";
import axios from "axios";

admin.initializeApp();

const REGION = "us-central1";
// You can override via env var if you want (GEMINI_MODEL)
const MODEL = process.env.GEMINI_MODEL || "gemini-1.5-flash";
// Stick to v1; v1beta can 404 with some model aliases
const API_VERSION = "v1";

export interface TaskOut {
  title: string;
  steps: string[];
  startTime?: string;
  endTime?: string;
  period?: "AM" | "PM";
}

function isTime12h(v: string): boolean {
  return /^(?:[1-9]|1[0-2]):[0-5][0-9]$/.test(v.trim());
}
function asString(x: unknown): string {
  return x === undefined || x === null ? "" : String(x);
}
function sanitizeTasks(input: unknown): TaskOut[] {
  const root = typeof input === "object" && input !== null ? (input as Record<string, unknown>) : {};
  const arr = Array.isArray((root as any).tasks) ? (root as any).tasks : [];
  const out: TaskOut[] = [];

  for (const item of arr.slice(0, 10)) {
    const obj = typeof item === "object" && item !== null ? (item as Record<string, unknown>) : {};
    const title = asString(obj.title).trim().slice(0, 60);
    const stepsRaw = Array.isArray(obj.steps) ? obj.steps : [];
    const steps = stepsRaw
      .slice(0, 8)
      .map((s: unknown) => asString(s).trim())
      .filter((s: string) => s.length > 0);

    const start = asString(obj.startTime).trim();
    const end = asString(obj.endTime).trim();
    const periodRaw = asString(obj.period).trim().toUpperCase();
    const period = periodRaw === "AM" || periodRaw === "PM" ? (periodRaw as "AM" | "PM") : undefined;

    out.push({
      title,
      steps,
      startTime: isTime12h(start) ? start : undefined,
      endTime: isTime12h(end) ? end : undefined,
      period,
    });
  }
  return out;
}

/** Callable (v1): generate tasks from a prompt. Requires auth (anon ok). */
export const generateTasksFromPrompt = functions
  .region(REGION)
  .https.onCall(async (data, ctx) => {
    if (!ctx.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login required.");
    }

    const prompt = asString((data as Record<string, unknown>)?.prompt).trim();
    if (!prompt) {
      throw new functions.https.HttpsError("invalid-argument", "Field 'prompt' is required.");
    }

    // Gemini key from env or functions:config
    const geminiKey =
      (process.env.GEMINI_API_KEY as string | undefined) ||
      ((functions.config().genai && (functions.config().genai as Record<string, string>).key) as string | undefined);

    if (!geminiKey) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        'Gemini key not set. Run: firebase functions:config:set genai.key="YOUR_GEMINI_API_KEY"'
      );
    }

    const instruction = [
      "You generate short, actionable daily tasks.",
      "Return STRICT JSON ONLY in this exact shape:",
      '{"tasks":[{"title":string,"steps":string[],"startTime":string,"endTime":string,"period":"AM"|"PM"}]}',
      "Rules:",
      '- Use 12-hour times like "8:00" / "8:10" (no leading zero on hour).',
      "- Titles <= 40 chars; 0–6 short steps.",
      "- Durations reasonable (5–120 minutes).",
      '- Keep period as "AM" or "PM".',
      "If a time is unknown, you may omit startTime/endTime/period.",
    ].join("\n");

    const body = {
      contents: [
        {
          role: "user",
          parts: [{ text: `${instruction}\n\nUser prompt:\n${prompt}` }],
        },
      ],
      generationConfig: { response_mime_type: "application/json" },
    };

    const url =
      `https://generativelanguage.googleapis.com/${API_VERSION}` +
      `/models/${MODEL}:generateContent?key=${encodeURIComponent(geminiKey)}`;

    let text = "{}";
    try {
      const resp = await axios.post(url, body, { headers: { "Content-Type": "application/json" } });

      const candidates = resp.data?.candidates || [];
      if (!Array.isArray(candidates) || candidates.length === 0) {
        functions.logger.error("Gemini returned no candidates", resp.data);
        throw new functions.https.HttpsError("internal", "AI response was empty.");
      }

      // Extract first text part
      const firstText =
        candidates[0]?.content?.parts?.find((p: any) => typeof p?.text === "string")?.text ??
        candidates[0]?.content?.parts?.[0]?.text ??
        "{}";

      text = String(firstText).trim();

      // Strip fenced code if present
      if (text.startsWith("```")) {
        text = text.replace(/^```(?:json)?/i, "").replace(/```$/, "").trim();
      }
    } catch (err: any) {
      const status = err?.response?.status;
      const data = err?.response?.data;
      functions.logger.error("Gemini HTTP error", { status, data, err: String(err), url, model: MODEL, api: API_VERSION });
      throw new functions.https.HttpsError(
        "internal",
        `Gemini HTTP ${status ?? "error"}`,
        typeof data === "object" ? data : String(data ?? err)
      );
    }

    // Parse and sanitize
    let parsed: unknown;
    try {
      parsed = JSON.parse(text);
    } catch {
      functions.logger.error("Invalid JSON from model", { text });
      throw new functions.https.HttpsError("internal", "Model returned invalid JSON.");
    }

    const tasks = sanitizeTasks(parsed);
    return { tasks };
  });