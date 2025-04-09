# Exo Docker Container (CPU-only)

This container runs [exo](https://github.com/exo-explore/exo) with tinygrad as the inference engine, optimized for CPU-only operation. It provides an OpenAI-compatible API for running large language models on CPU hardware.

## Quick Start

```bash
# Build the container
docker build -t exo-cpu:latest .

# Run with default settings (using host network for UDP discovery)
docker run --net=host \
  -v /path/to/models:/data/exo/downloads \
  -v /path/to/config:/data/exo/config \
  -v /path/to/temp:/data/exo/temp \
  exo-cpu:latest

# Or with Podman
podman build -t exo-cpu:latest .
podman run --net=host \
  -v /path/to/models:/data/exo/downloads \
  -v /path/to/config:/data/exo/config \
  -v /path/to/temp:/data/exo/temp \
  exo-cpu:latest
```

## Features

- CPU-only operation with tinygrad optimization
- OpenAI-compatible API endpoint (streaming and non-streaming)
- No external dependencies (self-contained)
- Works in disconnected environments
- Compatible with Docker and Podman
- Rootless operation with configurable UID/GID
- Built-in healthcheck
- API-focused (Web UI disabled by default)

## Volume Mounts

| Path | Description | Required | Purpose |
|------|-------------|----------|---------|
| `/data/exo/downloads` | Model storage location | Yes | Store model files that persist between container updates |
| `/data/exo/config` | Configuration files | No | Store customized config for exo |
| `/data/exo/temp` | Temporary files | No | Cache and temporary operations data |

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `EXO_HOME` | Base directory for exo data | `/data/exo` |
| `TINYGRAD_DEBUG` | Debug level for tinygrad (0-7) | `0` |
| `DEBUG` | Debug level for exo (0-9) | `0` |
| `CPU` | Force CPU mode in tinygrad | `1` |
| `CLANG` | Use Clang compiler for tinygrad | `1` |
| `OMP_NUM_THREADS` | Number of OpenMP threads | `4` |
| `MKL_NUM_THREADS` | Number of MKL threads | `4` |
| `OPENBLAS_NUM_THREADS` | Number of OpenBLAS threads | `4` |
| `VECLIB_MAXIMUM_THREADS` | Number of VecLib threads (Apple) | `4` |
| `DISABLE_COMPILER_CACHE` | Disable tinygrad compiler cache | `0` |
| `PUID` | User ID to run as (for rootless) | `1000` |
| `PGID` | Group ID to run as (for rootless) | `1000` |
| `NODE_ID` | Custom node ID | Auto-generated |
| `HF_ENDPOINT` | Alternative Hugging Face endpoint | huggingface.co |

## CPU Optimization

This container is optimized for CPU-only operation:

- Uses Clang compiler for best performance on modern CPUs
- Includes optimized math libraries (OpenBLAS, BLAS, LAPACK) 
- Controls thread allocation for optimal performance via environment variables
- Explicitly disables all GPU backends (CUDA, ROCm, Metal, AMD, NV)
- Verifies tinygrad installation during build
- Confirms CLANG and CPU environment variables are properly set
- Pre-configured for high-performance CPU inference
- Enables tinygrad compiler cache for better performance

## Networking Options

### Preferred: Host Network (Default)

By default, the container uses `--net=host` to allow UDP discovery to work properly:

```bash
docker run --net=host -v /path/to/models:/data/exo/downloads exo-cpu:latest
```

### Alternative: Manual Discovery

For environments where `--net=host` is not possible, you can expose the following ports and use manual discovery:

```bash
docker run \
  -p 52415:52415 \
  -p 5678:5678/udp \
  -v /path/to/models:/data/exo/downloads \
  -v /path/to/config:/data/exo/config \
  exo-cpu:latest \
  python -m exo.main --inference-engine tinygrad --discovery-module manual \
  --discovery-config-path /data/exo/config/discovery.json
```

You'll need to create a manual discovery config file at `/data/exo/config/discovery.json` with content like:

```json
{
  "nodes": [
    {
      "id": "node1",
      "address": "192.168.1.10",
      "port": 5678
    },
    {
      "id": "node2",
      "address": "192.168.1.11",
      "port": 5678
    }
  ]
}
```

## Supported Model Types

| Model Type | Endpoint | Examples |
|------------|----------|----------|
| LLM | `/v1/chat/completions` | LLaMA-3.2-3B, LLaMA-3.1-8B, Phi-3, Qwen |
| Vision | `/v1/chat/completions` | LLaVA-1.5-7B (multimodal) |
| Text Generation | `/v1/completions` | Any LLM model supported by tinygrad |

## Running without root

The container supports running as a non-root user with configurable UID/GID:

```bash
docker run --net=host \
  -e PUID=1001 -e PGID=1001 \
  -v /path/to/models:/data/exo/downloads \
  exo-cpu:latest
```

This is especially important for security or when running in environments that enforce rootless containers. The entrypoint script uses `gosu` to drop privileges and run as the specified user.

## Enabling the Web UI (Disabled by default)

The container runs without the web UI by default, focusing only on the API. To enable the web UI:

```bash
docker run --net=host \
  -v /path/to/models:/data/exo/downloads \
  exo-cpu:latest \
  python -m exo.main --inference-engine tinygrad
```

## Usage Examples

### Streaming API Request

```bash
curl http://localhost:52415/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
     "model": "llama-3.2-3b",
     "messages": [{"role": "user", "content": "What is distributed inference?"}],
     "temperature": 0.7,
     "stream": true
   }'
```

### Non-Streaming API Request

```bash
curl http://localhost:52415/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
     "model": "llama-3.2-3b",
     "messages": [{"role": "user", "content": "What is distributed inference?"}],
     "temperature": 0.7
   }'
```

## Performance Tuning

To optimize performance for your specific CPU, you can adjust the thread count environment variables:

```bash
docker run --net=host \
  -e OMP_NUM_THREADS=8 \
  -e MKL_NUM_THREADS=8 \
  -e OPENBLAS_NUM_THREADS=8 \
  -e VECLIB_MAXIMUM_THREADS=8 \
  -v /path/to/models:/data/exo/downloads \
  exo-cpu:latest
```

Setting these values to match your CPU core count can improve performance. For best results:

1. Set thread counts to match available physical cores
2. For machines with hyperthreading, try testing both physical core count and logical core count
3. For large models, consider setting `DISABLE_COMPILER_CACHE=0` to enable JIT cache

## Advanced Configuration Options

### tinygrad Compiler Cache

tinygrad uses a just-in-time (JIT) compiler for CPU operations. By default, the container enables the compiler cache to improve performance. To disable it:

```bash
docker run --net=host \
  -e DISABLE_COMPILER_CACHE=1 \
  -v /path/to/models:/data/exo/downloads \
  exo-cpu:latest
```

### Tailscale Discovery

If you're running in a Tailscale network, you can use the Tailscale discovery module:

```bash
docker run --net=host \
  -v /path/to/models:/data/exo/downloads \
  exo-cpu:latest \
  python -m exo.main --inference-engine tinygrad --discovery-module tailscale \
  --tailscale-api-key YOUR_API_KEY --tailnet-name YOUR_TAILNET
```

### Custom Node ID

To specify a custom node ID for identification in the cluster:

```bash
docker run --net=host \
  -e NODE_ID=my-custom-node \
  -v /path/to/models:/data/exo/downloads \
  exo-cpu:latest
```

## Debugging

To enable more verbose debugging, set the appropriate environment variables:

```bash
docker run --net=host \
  -e DEBUG=5 -e TINYGRAD_DEBUG=2 \
  -v /path/to/models:/data/exo/downloads \
  exo-cpu:latest
```

- `DEBUG` values (0-9): Higher values show more exo debugging info
- `TINYGRAD_DEBUG` values (0-7): Higher values show more tinygrad details including generated code
  - `1`: Lists devices being used
  - `2`: Provides performance metrics for operations
  - `3`: Outputs buffers used for each kernel
  - `4`: Outputs the generated kernel code
  - `5+`: Shows more detailed internal information

## Building the Container

Build the Docker image with:

```bash
docker build -t exo-cpu .
```

Or with Podman:

```bash
podman build -t exo-cpu .
```

The build process:
1. Uses Python 3.12 slim Debian as the base image
2. Installs necessary build dependencies and libraries
3. Clones the exo repository
4. Installs exo and its dependencies including tinygrad
5. Sets up the rootless user capabilities
6. Configures the volumes and entry point for container execution