#!/usr/bin/env node
"use strict";

const http = require("http");
const { spawn } = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");

const CODEX_MODEL_IDS = [
    "gpt-5.2-codex",
    "gpt-5.1-codex-max",
    "gpt-5.1-codex-mini",
    "gpt-5.2",
    "gpt-3.5-turbo",
    "gpt-4",
    "gpt-4o",
];

const GEMINI_MODEL_IDS = [
    "gemini-3-pro-preview",
    "gemini-3-flash-preview",
    "gemini-2.5-pro",
    "gemini-2.5-flash",
    "gemini-2.5-flash-lite",
    "gemini-2.0-flash-exp",
    "gemini-2.0-flash",
    "gemini-1.5-pro-latest",
    "gemini-1.5-flash-latest",
];

const CODEX_MODEL_ALIASES = {
    "gpt-3.5-turbo": null,
    "gpt-4": null,
    "gpt-4o": null,
    "codex-default": null,
};

const GEMINI_MODEL_ALIASES = {
    "gemini-default": null,
};

const OPENROUTER_MODELS_URL =
    process.env.OPENROUTER_MODELS_URL || "https://openrouter.ai/api/v1/models";
const OPENROUTER_REFRESH_MS = resolveInterval(
    process.env.OPENROUTER_REFRESH_MS,
    24 * 60 * 60 * 1000
);
const OPENROUTER_TIMEOUT_MS = resolveInterval(
    process.env.OPENROUTER_TIMEOUT_MS,
    15000
);
const OPENROUTER_VERIFY_TIMEOUT_MS = resolveInterval(
    process.env.OPENROUTER_VERIFY_TIMEOUT_MS,
    20000
);
const OPENROUTER_VERIFY_CONCURRENCY = resolvePositiveInt(
    process.env.OPENROUTER_VERIFY_CONCURRENCY,
    3
);
const OPENROUTER_VERIFY_PROMPT =
    process.env.OPENROUTER_VERIFY_PROMPT || "Reply with OK.";
const openrouterModelState = {
    codexModels: new Set(),
    geminiModels: new Set(),
    lastUpdated: null,
    refreshInFlight: false,
};

const CODEX_TIMEOUT_SECONDS = Number.parseInt(
    process.env.CODEX_TIMEOUT_SECONDS || "300",
    10
);
const PORT = Number.parseInt(process.env.CODEX_PASSTHROUGH_PORT || "8000", 10);
let serverOptions;
try {
    serverOptions = parseServerArgs(process.argv);
} catch (err) {
    console.error(err.message);
    console.error("Use --help to see available options.");
    process.exit(1);
}
const WORKSPACE_ROOT = resolveWorkspaceRoot(
    serverOptions.workspaceRoot || os.tmpdir()
);

class HttpError extends Error {
    constructor(status, message) {
        super(message);
        this.status = status;
    }
}

class AgentError extends Error {
    constructor(provider, message, stdout, stderr) {
        super(message);
        this.provider = provider;
        this.stdout = stdout;
        this.stderr = stderr;
    }
}

function resolveInterval(value, fallbackMs) {
    const parsed = Number.parseInt(value, 10);
    if (Number.isFinite(parsed) && parsed > 0) {
        return parsed;
    }
    return fallbackMs;
}

function resolvePositiveInt(value, fallback) {
    const parsed = Number.parseInt(value, 10);
    if (Number.isFinite(parsed) && parsed > 0) {
        return parsed;
    }
    return fallback;
}

function getOpenRouterApiKey() {
    return process.env.OPENROUTER_API_KEY || process.env.OR_API_KEY || "";
}

function normalizeCodexModel(model) {
    if (!model) {
        return model;
    }
    if (model.startsWith("openai/")) {
        return model.slice("openai/".length);
    }
    return model;
}

function normalizeGeminiModel(model) {
    if (!model) {
        return model;
    }
    if (model.startsWith("google/")) {
        return model.slice("google/".length);
    }
    if (model.includes("/gemini-")) {
        const parts = model.split("/");
        return parts[parts.length - 1];
    }
    return model;
}

function buildModelList(baseModels, extraModels) {
    const seen = new Set();
    const result = [];
    for (const model of baseModels) {
        if (!model || seen.has(model)) {
            continue;
        }
        seen.add(model);
        result.push(model);
    }
    const extras = Array.from(extraModels || []).filter(Boolean).sort();
    for (const model of extras) {
        if (seen.has(model)) {
            continue;
        }
        seen.add(model);
        result.push(model);
    }
    return result;
}

function getModelCatalog() {
    const codexModels =
        openrouterModelState.codexModels.size > 0
            ? Array.from(openrouterModelState.codexModels).sort()
            : CODEX_MODEL_IDS.slice();
    const geminiModels =
        openrouterModelState.geminiModels.size > 0
            ? Array.from(openrouterModelState.geminiModels).sort()
            : GEMINI_MODEL_IDS.slice();
    return {
        codexModels,
        geminiModels,
        allModels: [...codexModels, ...geminiModels],
    };
}

function jsonResponse(res, statusCode, payload) {
    const body = JSON.stringify(payload);
    res.writeHead(statusCode, {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(body),
    });
    res.end(body);
}

function printUsage() {
    const lines = [
        "Usage: api.js [options]",
        "",
        "Options:",
        "  -C, --cd <DIR>  Tell the agent to use the specified directory as its working root.",
        "  -h, --help      Show this help message.",
    ];
    console.log(lines.join("\n"));
}

function parseServerArgs(argv) {
    const options = { workspaceRoot: null };
    const args = argv.slice(2);
    for (let i = 0; i < args.length; i += 1) {
        const arg = args[i];
        if (arg === "-h" || arg === "--help") {
            printUsage();
            process.exit(0);
        }
        if (arg === "-C" || arg === "--cd") {
            const value = args[i + 1];
            if (!value || value.startsWith("-")) {
                throw new Error("Missing value for -C/--cd");
            }
            options.workspaceRoot = value;
            i += 1;
            continue;
        }
        if (arg.startsWith("--cd=")) {
            const value = arg.slice("--cd=".length);
            if (!value) {
                throw new Error("Missing value for --cd");
            }
            options.workspaceRoot = value;
            continue;
        }
        throw new Error(`Unknown argument: ${arg}`);
    }
    return options;
}

function resolveWorkspaceRoot(rootDir) {
    const resolved = path.resolve(rootDir);
    try {
        fs.mkdirSync(resolved, { recursive: true });
    } catch (err) {
        throw new Error(
            `Unable to create workspace root ${resolved}: ${err.message}`
        );
    }
    let stat;
    try {
        stat = fs.statSync(resolved);
    } catch (err) {
        throw new Error(
            `Unable to access workspace root ${resolved}: ${err.message}`
        );
    }
    if (!stat.isDirectory()) {
        throw new Error(`Workspace root is not a directory: ${resolved}`);
    }
    return resolved;
}

function parseJsonBody(req) {
    return new Promise((resolve, reject) => {
        let data = "";
        req.on("data", (chunk) => {
            data += chunk;
        });
        req.on("end", () => {
            if (!data.trim()) {
                resolve({});
                return;
            }
            try {
                resolve(JSON.parse(data));
            } catch (err) {
                reject(err);
            }
        });
        req.on("error", (err) => {
            reject(err);
        });
    });
}

function buildPromptFromMessages(messages) {
    if (!Array.isArray(messages)) {
        throw new HttpError(400, "Messages must be an array");
    }

    const lines = [];
    for (const msg of messages) {
        const content = typeof msg?.content === "string" ? msg.content.trim() : "";
        if (!content) {
            continue;
        }
        const role = typeof msg?.role === "string" ? msg.role.trim() : "";
        const normalizedRole = role ? role.toUpperCase() : "UNKNOWN";
        lines.push(`${normalizedRole}: ${content}`);
    }

    if (lines.length === 0) {
        throw new HttpError(400, "No message content found");
    }

    return lines.join("\n\n");
}

function buildCodexArgs({ model, outputPath, prompt }) {
    const args = [
        "exec",
        "--full-auto",
        "--skip-git-repo-check",
        "--output-last-message",
        outputPath,
    ];

    const normalizedModel = normalizeCodexModel(model);
    if (
        normalizedModel &&
        Object.prototype.hasOwnProperty.call(CODEX_MODEL_ALIASES, normalizedModel)
    ) {
        const mapped = CODEX_MODEL_ALIASES[normalizedModel];
        if (mapped) {
            args.push("--model", mapped);
        }
    } else if (normalizedModel) {
        args.push("--model", normalizedModel);
    }

    args.push(prompt);
    return args;
}

function buildGeminiArgs({ model, prompt }) {
    const args = ["--output-format", "text", "--approval-mode", "yolo"];

    const normalizedModel = normalizeGeminiModel(model);
    if (
        normalizedModel &&
        Object.prototype.hasOwnProperty.call(GEMINI_MODEL_ALIASES, normalizedModel)
    ) {
        const mapped = GEMINI_MODEL_ALIASES[normalizedModel];
        if (mapped) {
            args.push("--model", mapped);
        }
    } else if (normalizedModel) {
        args.push("--model", normalizedModel);
    }

    args.push(prompt);
    return args;
}

function isGeminiModel(model) {
    if (!model) {
        return false;
    }
    if (Object.prototype.hasOwnProperty.call(GEMINI_MODEL_ALIASES, model)) {
        return true;
    }
    const normalizedModel = normalizeGeminiModel(model);
    if (GEMINI_MODEL_IDS.includes(normalizedModel)) {
        return true;
    }
    if (openrouterModelState.geminiModels.has(normalizedModel)) {
        return true;
    }
    return normalizedModel.startsWith("gemini-");
}

function resolveProvider(model) {
    return isGeminiModel(model) ? "gemini" : "codex";
}

function readOutputFile(outputPath) {
    try {
        return fs.readFileSync(outputPath, "utf8");
    } catch (err) {
        return "";
    }
}

function createTempWorkspace() {
    const prefix = path.join(WORKSPACE_ROOT, "codex_workspace_");
    return fs.mkdtempSync(prefix);
}

function removeTempWorkspace(workspaceDir) {
    if (!workspaceDir) {
        return;
    }
    try {
        fs.rmSync(workspaceDir, { recursive: true, force: true });
    } catch (err) {
        try {
            fs.rmdirSync(workspaceDir, { recursive: true });
        } catch (err2) {
            // Best-effort cleanup.
        }
    }
}

function createTempOutputPath(workspaceDir) {
    const filename = `codex_response_${Date.now()}_${crypto.randomUUID()}.txt`;
    const outputPath = path.join(workspaceDir, filename);
    fs.closeSync(fs.openSync(outputPath, "w"));
    return outputPath;
}

function spawnCli(command, args, timeoutMs, options = {}) {
    return new Promise((resolve, reject) => {
        const child = spawn(command, args, {
            stdio: ["ignore", "pipe", "pipe"],
            cwd: options.cwd,
        });
        let stdout = "";
        let stderr = "";
        let finished = false;

        const timeoutId = setTimeout(() => {
            if (finished) {
                return;
            }
            finished = true;
            child.kill("SIGKILL");
            const err = new Error("CLI execution timed out");
            err.code = "TIMEOUT";
            reject(err);
        }, timeoutMs);

        child.stdout.on("data", (chunk) => {
            stdout += chunk.toString();
        });
        child.stderr.on("data", (chunk) => {
            stderr += chunk.toString();
        });

        child.on("error", (err) => {
            if (finished) {
                return;
            }
            finished = true;
            clearTimeout(timeoutId);
            reject(err);
        });

        child.on("close", (code) => {
            if (finished) {
                return;
            }
            finished = true;
            clearTimeout(timeoutId);
            resolve({ code, stdout, stderr });
        });
    });
}

async function probeModel(provider, model) {
    const workspaceDir = createTempWorkspace();
    const outputPath = provider === "codex" ? createTempOutputPath(workspaceDir) : null;
    try {
        let args;
        let result;
        if (provider === "gemini") {
            args = buildGeminiArgs({ model, prompt: OPENROUTER_VERIFY_PROMPT });
            result = await spawnCli("gemini", args, OPENROUTER_VERIFY_TIMEOUT_MS, {
                cwd: workspaceDir,
            });
        } else {
            args = buildCodexArgs({
                model,
                outputPath,
                prompt: OPENROUTER_VERIFY_PROMPT,
            });
            result = await spawnCli("codex", args, OPENROUTER_VERIFY_TIMEOUT_MS, {
                cwd: workspaceDir,
            });
        }
        if (result.code !== 0) {
            return false;
        }
        const content =
            provider === "codex"
                ? readOutputFile(outputPath) || result.stdout || ""
                : result.stdout || "";
        return Boolean(content.trim());
    } catch (err) {
        return false;
    } finally {
        if (outputPath) {
            try {
                fs.unlinkSync(outputPath);
            } catch (err) {
                // Best-effort cleanup.
            }
        }
        removeTempWorkspace(workspaceDir);
    }
}

async function verifyModels(models, provider) {
    const verified = new Set();
    if (!models || models.length === 0) {
        return verified;
    }
    let cursor = 0;
    const concurrency = Math.min(
        Math.max(OPENROUTER_VERIFY_CONCURRENCY, 1),
        models.length
    );
    const workers = Array.from({ length: concurrency }, async () => {
        while (cursor < models.length) {
            const index = cursor;
            cursor += 1;
            const model = models[index];
            if (!model) {
                continue;
            }
            const ok = await probeModel(provider, model);
            if (ok) {
                verified.add(model);
            }
        }
    });
    await Promise.all(workers);
    return verified;
}

function extractOpenRouterModels(payload) {
    const codexModels = new Set();
    const geminiModels = new Set();
    const data = Array.isArray(payload?.data) ? payload.data : [];

    for (const entry of data) {
        const id = typeof entry?.id === "string" ? entry.id.trim() : "";
        if (!id) {
            continue;
        }
        const architecture = entry?.architecture || {};
        const inputModalities = Array.isArray(architecture.input_modalities)
            ? architecture.input_modalities
            : [];
        const outputModalities = Array.isArray(architecture.output_modalities)
            ? architecture.output_modalities
            : [];
        if (
            !inputModalities.includes("text") ||
            !outputModalities.includes("text")
        ) {
            continue;
        }
        if (id.startsWith("openai/")) {
            const modelName = normalizeCodexModel(id);
            if (modelName) {
                codexModels.add(modelName);
            }
        }
        if (id.includes("/gemini-")) {
            const modelName = normalizeGeminiModel(id);
            if (modelName) {
                geminiModels.add(modelName);
            }
        }
    }

    return {
        codexModels: Array.from(codexModels).sort(),
        geminiModels: Array.from(geminiModels).sort(),
    };
}

async function refreshOpenRouterModels() {
    const apiKey = getOpenRouterApiKey();
    if (!apiKey) {
        return;
    }
    if (openrouterModelState.refreshInFlight) {
        return;
    }
    openrouterModelState.refreshInFlight = true;

    try {
        const args = [
            "-fsSL",
            OPENROUTER_MODELS_URL,
            "-H",
            `Authorization: Bearer ${apiKey}`,
        ];

        const result = await spawnCli("curl", args, OPENROUTER_TIMEOUT_MS);
        if (result.code !== 0) {
            const stderr = (result.stderr || "").trim();
            throw new Error(
                `OpenRouter fetch failed rc=${result.code} stderr=${stderr.slice(0, 2000)}`
            );
        }

        let payload;
        try {
            payload = JSON.parse(result.stdout || "{}");
        } catch (err) {
            throw new Error("OpenRouter response was not valid JSON");
        }

        const { codexModels, geminiModels } = extractOpenRouterModels(payload);
        const [verifiedCodex, verifiedGemini] = await Promise.all([
            verifyModels(codexModels, "codex"),
            verifyModels(geminiModels, "gemini"),
        ]);

        if (codexModels.length > 0) {
            if (verifiedCodex.size > 0) {
                openrouterModelState.codexModels = verifiedCodex;
            } else {
                console.warn(
                    "OpenRouter verification produced no working Codex models; keeping previous list."
                );
            }
        }

        if (geminiModels.length > 0) {
            if (verifiedGemini.size > 0) {
                openrouterModelState.geminiModels = verifiedGemini;
            } else {
                console.warn(
                    "OpenRouter verification produced no working Gemini models; keeping previous list."
                );
            }
        }

        openrouterModelState.lastUpdated = Date.now();
        console.log(
            `OpenRouter models updated: codex=${openrouterModelState.codexModels.size} gemini=${openrouterModelState.geminiModels.size}`
        );
    } finally {
        openrouterModelState.refreshInFlight = false;
    }
}

function scheduleOpenRouterRefresh() {
    if (!getOpenRouterApiKey()) {
        console.log("OpenRouter API key missing; skipping model refresh.");
        return;
    }

    refreshOpenRouterModels().catch((err) => {
        console.warn(`OpenRouter refresh failed: ${err.message}`);
    });

    const interval = setInterval(() => {
        refreshOpenRouterModels().catch((err) => {
            console.warn(`OpenRouter refresh failed: ${err.message}`);
        });
    }, OPENROUTER_REFRESH_MS);

    if (typeof interval.unref === "function") {
        interval.unref();
    }
}

async function handleChatCompletions(req, res) {
    let payload;
    try {
        payload = await parseJsonBody(req);
    } catch (err) {
        jsonResponse(res, 400, { detail: "Invalid JSON body" });
        return;
    }

    const model = typeof payload.model === "string" ? payload.model : "codex-default";
    let prompt;
    try {
        prompt = buildPromptFromMessages(payload.messages);
    } catch (err) {
        const status = err instanceof HttpError ? err.status : 400;
        jsonResponse(res, status, { detail: err.message || "Invalid request" });
        return;
    }

    const provider = resolveProvider(model);
    const providerLabel = provider === "gemini" ? "Gemini" : "Codex";
    console.log(
        `Received ${payload.messages?.length || 0} messages; prompt length=${prompt.length}; model=${model}; provider=${provider}`
    );

    const workspaceDir = createTempWorkspace();
    const outputPath = provider === "codex" ? createTempOutputPath(workspaceDir) : null;
    try {
        let args;
        let result;
        if (provider === "gemini") {
            args = buildGeminiArgs({ model, prompt });
            console.log(`Executing gemini with model=${model} in temp workspace`);
            result = await spawnCli("gemini", args, CODEX_TIMEOUT_SECONDS * 1000, {
                cwd: workspaceDir,
            });
        } else {
            args = buildCodexArgs({ model, outputPath, prompt });
            console.log(`Executing codex with model=${model} in temp workspace`);
            result = await spawnCli("codex", args, CODEX_TIMEOUT_SECONDS * 1000, {
                cwd: workspaceDir,
            });
        }
        if (result.code !== 0) {
            const stderr = (result.stderr || "").trim();
            const stdout = (result.stdout || "").trim();
            console.error(
                `${providerLabel} failed rc=${result.code} stderr=${stderr.slice(
                    0,
                    5000
                )} stdout=${stdout.slice(0, 5000)}`
            );
            throw new AgentError(providerLabel, stderr || "unknown error", stdout, stderr);
        }

        let content = "";
        if (provider === "codex") {
            content = readOutputFile(outputPath) || result.stdout || "";
        } else {
            content = result.stdout || "";
        }
        if (!content.trim()) {
            content = `Error: No response generated by ${providerLabel}.`;
        }

        jsonResponse(res, 200, {
            id: `chatcmpl-${crypto.randomUUID()}`,
            object: "chat.completion",
            created: Math.floor(Date.now() / 1000),
            model,
            choices: [
                {
                    index: 0,
                    message: {
                        role: "assistant",
                        content,
                    },
                    finish_reason: "stop",
                },
            ],
            usage: {
                prompt_tokens: 0,
                completion_tokens: 0,
                total_tokens: 0,
            },
        });
    } catch (err) {
        if (err && err.code === "TIMEOUT") {
            jsonResponse(res, 504, { detail: `${providerLabel} execution timed out` });
            return;
        }
        if (err instanceof AgentError) {
            jsonResponse(res, 500, {
                detail: `${err.provider} execution failed: ${err.message || "unknown error"}`,
            });
            return;
        }
        console.error("Unhandled server error", err);
        jsonResponse(res, 500, { detail: err.message || "Unhandled server error" });
    } finally {
        if (outputPath) {
            try {
                fs.unlinkSync(outputPath);
            } catch (err) {
                // Best-effort cleanup.
            }
        }
        removeTempWorkspace(workspaceDir);
    }
}

const server = http.createServer(async (req, res) => {
    const url = new URL(req.url || "/", "http://localhost");

    if (req.method === "GET" && url.pathname === "/") {
        jsonResponse(res, 200, { status: "ok", service: "codex-passthrough" });
        return;
    }

    if (req.method === "GET" && url.pathname === "/v1/models") {
        const now = Math.floor(Date.now() / 1000);
        const { allModels } = getModelCatalog();
        const data = allModels.map((modelId) => ({
            id: modelId,
            object: "model",
            created: now,
            owned_by: resolveProvider(modelId),
        }));
        jsonResponse(res, 200, { object: "list", data });
        return;
    }

    if (req.method === "POST" && url.pathname === "/v1/chat/completions") {
        await handleChatCompletions(req, res);
        return;
    }

    jsonResponse(res, 404, { detail: "Not found" });
});

scheduleOpenRouterRefresh();

server.listen(PORT, "0.0.0.0", () => {
    console.log(
        `Codex passthrough listening on 0.0.0.0:${PORT} (workspace root: ${WORKSPACE_ROOT})`
    );
});
