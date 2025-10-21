"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateTasksFromPrompt = void 0;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const options_1 = require("firebase-functions/v2/options");
// ---- Firebase init & region (v2 style) ----
admin.initializeApp();
// Change if you deployed to another region.
(0, options_1.setGlobalOptions)({ region: "us-central1" });
// ---- Utilities ----
function isTime12h(v) {
    return /^(?:[1-9]|1[0-2]):[0-5][0-9]$/.test(v.trim());
}
function asString(x) {
    return x === undefined || x === null ? "" : String(x);
}
function sanitizeTasks(input) {
    const root = typeof input === "object" && input !== null
        ? input
        : {};
    const arr = Array.isArray(root.tasks) ? root.tasks : [];
    const out = [];
    for (const item of arr.slice(0, 10)) {
        const obj = typeof item === "object" && item !== null
            ? item
            : {};
        const title = asString(obj.title).trim().slice(0, 60);
        const stepsRaw = Array.isArray(obj.steps) ? obj.steps : [];
        const steps = stepsRaw
            .slice(0, 8)
            .map((s) => asString(s).trim())
            .filter((s) => s.length > 0);
        const start = asString(obj.startTime).trim();
        const end = asString(obj.endTime).trim();
        const periodRaw = asString(obj.period).trim().toUpperCase();
        const period = periodRaw === "AM" || periodRaw === "PM"
            ? periodRaw
            : undefined;
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
// ---- Callable (v2): generate tasks from a prompt. Requires auth. ----
exports.generateTasksFromPrompt = (0, https_1.onCall)(
// You can also set { concurrency: 5 } etc. here
{ cors: true }, async (req) => {
    if (!req.auth) {
        throw new https_1.HttpsError("unauthenticated", "Login required.");
    }
    const data = req.data ?? {};
    const prompt = asString(data.prompt).trim();
    if (!prompt) {
        throw new https_1.HttpsError("invalid-argument", "Field 'prompt' is required.");
    }
    // Get API key from Secret or legacy functions:config
    const keyFromEnv = process.env.OPENAI_API_KEY;
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const v1cfg = require("firebase-functions")
        .config?.();
    const keyFromConfig = (v1cfg?.openai && v1cfg.openai.key);
    const apiKey = keyFromEnv || keyFromConfig;
    if (!apiKey) {
        throw new https_1.HttpsError("failed-precondition", "OpenAI key not set. Use one of:\n" +
            '  firebase functions:secrets:set OPENAI_API_KEY\n' +
            'or\n' +
            '  firebase functions:config:set openai.key="YOUR_KEY"');
    }
});
