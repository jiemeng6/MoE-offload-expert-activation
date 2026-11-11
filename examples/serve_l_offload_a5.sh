#!/usr/bin/env bash
# Run inside the existing A5 runtime, from the L vLLM-Ascend checkout.
set -euo pipefail

if [[ $# -ne 2 || ! ${2:-} =~ ^[0-9]+$ ]]; then
    printf 'Usage: bash %s /path/to/DeepSeek-V4-Flash-0731 NPU_DEVICE_ID\n' "$0" >&2
    exit 2
fi

model_dir=$1
device_id=$2
ascend_src=$(cd -- "${L_OFFLOAD_ASCEND_SRC:-$PWD}" && pwd -P)
if [[ ! -f "$ascend_src/vllm_ascend/worker/v2/dspark_expert_pool.py" ]]; then
    printf 'Set L_OFFLOAD_ASCEND_SRC to the L vLLM-Ascend checkout.\n' >&2
    exit 2
fi

case ${L_OFFLOAD_MODE:-l} in
    l)
        additional_config='{"expert_offload_config":{"enabled":true,"num_device_experts":84},"dspark_expert_pool":{"enabled":true,"protected_positions":2,"suffix_experts":0}}'
        ;;
    baseline)
        additional_config='{"expert_offload_config":{"enabled":true,"num_device_experts":84}}'
        ;;
    *)
        printf 'L_OFFLOAD_MODE must be l or baseline.\n' >&2
        exit 2
        ;;
esac

export ASCEND_RT_VISIBLE_DEVICES="$device_id"
export VLLM_USE_V2_MODEL_RUNNER=1
export PYTHONPATH="$ascend_src${PYTHONPATH:+:$PYTHONPATH}"

cmd=(
    vllm serve "$model_dir"
    --host "${L_OFFLOAD_HOST:-127.0.0.1}"
    --port "${L_OFFLOAD_PORT:-18861}"
    --served-model-name dsv4
    --tokenizer-mode deepseek_v4
    --tensor-parallel-size 1
    --max-num-seqs 2
    --max-model-len "${L_OFFLOAD_MAX_MODEL_LEN:-8192}"
    --max-num-batched-tokens 2048
    --enable-chunked-prefill
    --no-async-scheduling
    --block-size 32
    --kv-cache-dtype fp8
    --kv-cache-memory-bytes 3221225472
    --speculative-config '{"method":"dspark","num_speculative_tokens":5,"enforce_eager":true}'
    --compilation-config '{"mode":0,"cudagraph_mode":"FULL_DECODE_ONLY","cudagraph_capture_sizes":[1,2,6,12]}'
    --additional-config "$additional_config"
)

if [[ ${L_OFFLOAD_DRY_RUN:-0} == 1 ]]; then
    printf 'ASCEND_RT_VISIBLE_DEVICES=%q VLLM_USE_V2_MODEL_RUNNER=1 PYTHONPATH=%q ' "$device_id" "$PYTHONPATH"
    printf '%q ' "${cmd[@]}"
    printf '\n'
    exit 0
fi

if [[ ! -r "$model_dir/config.json" ]]; then
    printf 'Local checkpoint config.json is missing under %s.\n' "$model_dir" >&2
    exit 2
fi

exec "${cmd[@]}"
