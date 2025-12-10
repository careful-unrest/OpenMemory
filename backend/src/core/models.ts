import { readFileSync, existsSync } from "fs";
import { join } from "path";
interface model_cfg {
    [sector: string]: Record<string, string>;
}
let cfg: model_cfg | null = null;

const find_models_file = (): string | null => {
    const paths = [
        join(__dirname, "../../../models.yml"),
        "/app/models.yml",
        join(process.cwd(), "models.yml"),
    ];
    for (const p of paths) {
        if (existsSync(p)) return p;
    }
    return null;
};

export const load_models = (): model_cfg => {
    if (cfg) return cfg;
    const p = find_models_file();
    if (!p) {
        console.warn("[MODELS] models.yml not found, using defaults");
        cfg = get_defaults();
        return cfg;
    }
    try {
        const yml = readFileSync(p, "utf-8");
        cfg = parse_yaml(yml);
        console.log(
            `[MODELS] Loaded models.yml from ${p} (${Object.keys(cfg).length} sectors)`,
        );
        return cfg;
    } catch (e) {
        console.error("[MODELS] Failed to parse models.yml:", e);
        cfg = get_defaults();
        return cfg;
    }
};

const parse_yaml = (yml: string): model_cfg => {
    const lines = yml.split("\n");
    const obj: model_cfg = {};
    let cur_sec: string | null = null;
    for (const line of lines) {
        const trim = line.trim();
        if (!trim || trim.startsWith("#")) continue;
        const indent = line.search(/\S/);
        const [key, ...val_parts] = trim.split(":");
        const val = val_parts.join(":").trim();
        if (indent === 0 && val) {
            continue;
        } else if (indent === 0) {
            cur_sec = key;
            obj[cur_sec] = {};
        } else if (cur_sec && val) {
            obj[cur_sec][key] = val;
        }
    }
    return obj;
};

const get_defaults = (): model_cfg => ({
    episodic: {
        ollama: "nomic-embed-text",
        openai: "text-embedding-3-small",
        gemini: "gemini-embedding-001",
        aws: "amazon.titan-embed-text-v2:0",
        local: "all-MiniLM-L6-v2",
    },
    semantic: {
        ollama: "nomic-embed-text",
        openai: "text-embedding-3-small",
        gemini: "gemini-embedding-001",
        aws: "amazon.titan-embed-text-v2:0",
        local: "all-MiniLM-L6-v2",
    },
    procedural: {
        ollama: "nomic-embed-text",
        openai: "text-embedding-3-small",
        gemini: "gemini-embedding-001",
        aws: "amazon.titan-embed-text-v2:0",
        local: "all-MiniLM-L6-v2",
    },
    emotional: {
        ollama: "nomic-embed-text",
        openai: "text-embedding-3-small",
        gemini: "gemini-embedding-001",
        aws: "amazon.titan-embed-text-v2:0",
        local: "all-MiniLM-L6-v2",
    },
    reflective: {
        ollama: "nomic-embed-text",
        openai: "text-embedding-3-large",
        gemini: "gemini-embedding-001",
        aws: "amazon.titan-embed-text-v2:0",
        local: "all-mpnet-base-v2",
    },
});

export const get_model = (sector: string, provider: string): string => {
    const cfg = load_models();
    return (
        cfg[sector]?.[provider] ||
        cfg.semantic?.[provider] ||
        "nomic-embed-text"
    );
};

export const get_provider_config = (provider: string): any => {
    return {};
};
