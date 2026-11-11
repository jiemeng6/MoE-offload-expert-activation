# L 专家卸载启动脚本使用说明

[`serve_l_offload_a5.sh`](serve_l_offload_a5.sh) 在单张 Ascend A5 上启动 DeepSeek-V4-Flash-0731 服务，默认开启 L 路由。

## 运行环境

- 使用 Ascend 950PR 或 950DT（A5），在已有的 CANN、PyTorch 和 TorchNPU 环境中运行。环境里的 `vllm` 命令应可用。
- 使用本仓库的 L 分支。上游专家卸载验证使用的 vLLM 提交为 [`24420b7`](https://github.com/vllm-project/vllm/commit/24420b7a341af37a9bc3186e6fc6062512e0aa58)。
- 准备本地 DeepSeek-V4-Flash-0731 模型目录，目录内须有可读的 `config.json`，专家权重采用原生 W4A8 MXFP 格式。
- 如果模型使用物理块大小不同的 draft KV 缓存组，运行的 vLLM-Ascend 源码需包含 [draft KV block size 修正 #20429](https://github.com/vllm-project/vllm-ascend/pull/20429)。上游整模验证使用了该修正。

## 启动服务

进入仓库根目录，换成实际模型目录和芯片 ID 后执行：

```bash
bash examples/serve_l_offload_a5.sh /models/DeepSeek-V4-Flash-0731 0
```

第一个参数是模型目录，第二个参数是当前运行环境里的单个 NPU 芯片 ID。脚本在前台运行，按 `Ctrl+C` 停止服务。

| 默认项 | 配置 |
| --- | --- |
| 服务地址和模型名 | `127.0.0.1:18861`，`dsv4` |
| 设备与执行器 | 单芯片、TP1、ModelRunner V2 |
| 专家卸载 | 每层 84 个专家槽位，启用 L 的 P2E0 |
| 投机解码 | DSpark5，每条完整验证含 1 个 anchor 和 5 个草稿位置 |
| 解码图 | `FULL_DECODE_ONLY`，配置的捕获尺寸为 `[1, 2, 6, 12]` |
| 调度与长度 | 单步最多调度 2 条序列，默认最大模型长度 8192 token |

## 确认服务可用

服务启动后，在同一运行环境的另一个终端检查健康状态和模型名：

```bash
curl -fsS http://127.0.0.1:18861/health
curl -fsS http://127.0.0.1:18861/v1/models
```

`/health` 返回 HTTP 200 即通过，响应正文可能为空。`/v1/models` 应列出 `dsv4`。可以再发一条短请求确认生成：

```bash
curl -fsS http://127.0.0.1:18861/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"dsv4","messages":[{"role":"user","content":"用一句话介绍你自己。"}],"max_tokens":32}'
```

## 切换基线或修改参数

在同一芯片上对照时，先停止 L 服务，再用 `baseline` 模式启动。这个模式保留 84 槽专家卸载和 DSpark5，关闭 L 路由。

```bash
L_OFFLOAD_MODE=baseline bash examples/serve_l_offload_a5.sh /models/DeepSeek-V4-Flash-0731 0
```

| 环境变量 | 默认值 | 用途 |
| --- | --- | --- |
| `L_OFFLOAD_MODE` | `l` | 用 `baseline` 切换到原生路由的专家卸载 |
| `L_OFFLOAD_PORT` | `18861` | 设置服务端口 |
| `L_OFFLOAD_HOST` | `127.0.0.1` | 设置服务监听地址 |
| `L_OFFLOAD_MAX_MODEL_LEN` | `8192` | 设置最大模型长度 |
| `L_OFFLOAD_ASCEND_SRC` | 当前目录 | 从仓库根目录以外运行时，指向 L 版 vLLM-Ascend 仓库根目录 |

覆盖监听地址或端口后，检查服务时使用对应的地址。若脚本提示找不到 `config.json`，检查模型目录；若提示找不到 L 源码，检查当前目录或 `L_OFFLOAD_ASCEND_SRC`。
