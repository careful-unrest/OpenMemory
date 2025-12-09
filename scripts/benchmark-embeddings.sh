#!/bin/bash
# Benchmark embedding generation latency
# Tests with ~1K tokens of input text

OLLAMA_URL="${1:-http://localhost:11434}"
MODEL="${2:-nomic-embed-text}"
CONTAINER="${3:-openmemory-ollama-1}"
RUNS=5

# Short text (~50 tokens) - typical user message
TEXT_SHORT="I'm working on a React project with TypeScript and need help setting up authentication using NextAuth. The app uses PostgreSQL for the database."

# Long text (~1K tokens) - document/context embedding
TEXT_LONG="The field of artificial intelligence has undergone remarkable transformations since its inception in the mid-twentieth century. Early pioneers like Alan Turing, John McCarthy, and Marvin Minsky laid the theoretical foundations that would eventually lead to the sophisticated systems we see today. Machine learning, a subset of AI, has proven particularly revolutionary, enabling computers to learn from data rather than following explicitly programmed instructions.

Deep learning, which emerged as a dominant paradigm in the 2010s, uses neural networks with multiple layers to process information in increasingly abstract ways. These networks, inspired by the structure of biological brains, have achieved unprecedented success in tasks like image recognition, natural language processing, and game playing. The transformer architecture, introduced in 2017, revolutionized how machines understand and generate human language.

Large language models trained on vast corpora of text have demonstrated emergent capabilities that surprised even their creators. These models can engage in complex reasoning, write code, translate between languages, and assist with creative tasks. However, they also raise important questions about safety, alignment, and the future relationship between humans and intelligent machines.

The integration of AI into everyday applications continues to accelerate. From recommendation systems that curate our digital experiences to autonomous vehicles navigating complex environments, artificial intelligence is reshaping industries and societies. Healthcare applications show particular promise, with AI systems assisting in diagnosis, drug discovery, and personalized treatment planning.

Ethical considerations remain paramount as these technologies advance. Questions of bias, transparency, accountability, and the potential displacement of human workers require careful consideration. Researchers and policymakers worldwide are working to develop frameworks that ensure AI benefits humanity while minimizing potential harms. The coming decades will likely see even more profound changes as artificial general intelligence moves from speculation toward possibility."

echo "=== Ollama Embedding Benchmark ==="
echo "URL: $OLLAMA_URL"
echo "Model: $MODEL"
echo "Container: $CONTAINER"
echo "Runs per test: $RUNS"
echo ""

# Check if container exists for stats
MONITOR_STATS=false
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    MONITOR_STATS=true
    echo "Container found - will monitor CPU/RAM"
else
    echo "Container '$CONTAINER' not found - skipping resource monitoring"
fi
echo ""

# Check if ollama is reachable
if ! curl -sf "$OLLAMA_URL/api/tags" > /dev/null 2>&1; then
    echo "ERROR: Cannot reach Ollama at $OLLAMA_URL"
    exit 1
fi

# Check if model exists
if ! curl -sf "$OLLAMA_URL/api/tags" | grep -q "$MODEL"; then
    echo "WARNING: Model $MODEL may not be available"
fi

# Function to run benchmark for a given text
run_benchmark() {
    local TEXT="$1"
    local LABEL="$2"
    local TOKEN_EST="$3"

    echo "--- $LABEL (~$TOKEN_EST tokens, ${#TEXT} chars) ---"
    echo ""

    local total_ms=0
    local times=()
    local cpu_samples=()
    local mem_samples=()

    # Create JSON payload file
    local PAYLOAD_FILE=$(mktemp)
    jq -n --arg model "$MODEL" --arg prompt "$TEXT" '{model: $model, prompt: $prompt}' > "$PAYLOAD_FILE"

    for i in $(seq 1 $RUNS); do
        # Start stats collection in background
        if $MONITOR_STATS; then
            local STATS_FILE=$(mktemp)
            (
                while true; do
                    docker stats --no-stream --format "{{.CPUPerc}} {{.MemUsage}}" "$CONTAINER" 2>/dev/null >> "$STATS_FILE"
                    sleep 0.1
                done
            ) &
            local STATS_PID=$!
        fi

        local start=$(date +%s%3N)

        local result=$(curl -sf "$OLLAMA_URL/api/embeddings" \
            -H "Content-Type: application/json" \
            -d @"$PAYLOAD_FILE" 2>&1)

        local end=$(date +%s%3N)
        local elapsed=$((end - start))

        # Stop stats collection
        if $MONITOR_STATS; then
            kill $STATS_PID 2>/dev/null
            wait $STATS_PID 2>/dev/null

            # Parse peak CPU and memory from samples
            if [ -s "$STATS_FILE" ]; then
                local peak_cpu=$(awk '{gsub(/%/,"",$1); if($1>max)max=$1} END{print max}' "$STATS_FILE")
                local peak_mem=$(awk '{print $2}' "$STATS_FILE" | sort -h | tail -1)
                cpu_samples+=("$peak_cpu")
                mem_samples+=("$peak_mem")
            fi
            rm -f "$STATS_FILE"
        fi

        if echo "$result" | grep -q '"embedding"'; then
            times+=($elapsed)
            total_ms=$((total_ms + elapsed))
            if $MONITOR_STATS && [ -n "$peak_cpu" ]; then
                echo "  Run $i: ${elapsed}ms | CPU: ${peak_cpu}% | RAM: ${peak_mem}"
            else
                echo "  Run $i: ${elapsed}ms"
            fi
        else
            echo "  Run $i: FAILED"
            echo "  $result"
        fi
    done

    rm -f "$PAYLOAD_FILE"

    echo ""

    if [ ${#times[@]} -gt 0 ]; then
        local avg=$((total_ms / ${#times[@]}))

        # Find min/max
        local min=${times[0]}
        local max=${times[0]}
        for t in "${times[@]}"; do
            ((t < min)) && min=$t
            ((t > max)) && max=$t
        done

        echo "  Results: avg=${avg}ms, min=${min}ms, max=${max}ms"

        # Estimate throughput
        if [ $avg -gt 0 ]; then
            local tps=$((1000 * 100 / avg))
            echo "  Throughput: ~$((tps / 100)).$((tps % 100)) embeddings/sec"
        fi

        # Resource summary
        if $MONITOR_STATS && [ ${#cpu_samples[@]} -gt 0 ]; then
            local max_cpu=0
            for c in "${cpu_samples[@]}"; do
                local c_int=${c%.*}
                [ "$c_int" -gt "$max_cpu" ] 2>/dev/null && max_cpu=$c_int
            done
            echo "  Peak CPU: ${max_cpu}% | Peak RAM: ${mem_samples[-1]}"
        fi
    else
        echo "  All runs failed"
    fi
    echo ""
}

# Run benchmarks
echo "Running benchmarks..."
echo ""

run_benchmark "$TEXT_SHORT" "SHORT (user message)" "50"
run_benchmark "$TEXT_LONG" "LONG (document)" "1000"
