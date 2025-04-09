FROM python:3.12-slim-bookworm

# Set environment variables to force CPU-only mode and optimize for performance
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONIOENCODING=utf-8 \
    PYTHONFAULTHANDLER=1 \
    # Force tinygrad to use CPU backend with Clang
    CLANG=1 \
    CPU=1 \
    # Explicitly disable all GPU backends
    GPU=0 \
    CUDA=0 \
    METAL=0 \
    AMD=0 \
    NV=0 \
    WEBGPU=0 \
    # Control debugging level (0-7)
    TINYGRAD_DEBUG=0 \
    DEBUG=0 \
    # Multithreading optimization 
    # (these will be runtime configurable via env vars)
    OMP_NUM_THREADS=4 \
    MKL_NUM_THREADS=4 \
    OPENBLAS_NUM_THREADS=4 \
    VECLIB_MAXIMUM_THREADS=4 \
    # Cache control for tinygrad
    DISABLE_COMPILER_CACHE=0 \
    # Set lower default log level
    PYTHONWARNINGS="ignore" \
    # Base directory for exo data
    EXO_HOME=/data/exo \
    # Path configuration
    PYTHONPATH=/app \
    # Default to Clang as C compiler
    CC=clang

# Install required dependencies 
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build tools for compiling code
    build-essential \
    clang \
    # Git for source code
    git \
    # Certificates for secure downloads
    ca-certificates \
    # Math libraries for CPU optimization
    libblas-dev \
    liblapack-dev \
    libopenblas-dev \
    # For healthcheck
    curl \
    # For dropping privileges
    gosu \
    # Added Dependencies for CPU Only
    libgl1-mesa-glx libgl1-mesa-dev clang \
    # Cleanup
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create necessary directories
RUN mkdir -p /app /data/exo/downloads /data/exo/config /data/exo/temp

# Set working directory
WORKDIR /app

# Clone exo from GitHub first
RUN git clone https://github.com/exo-explore/exo.git /app/exo

# Set working directory to exo for installation
WORKDIR /app/exo

# Install Python dependencies
RUN pip install numba llvmlite

# Install exo with CPU-optimized dependencies
RUN pip install --no-cache-dir -e . \
    # Install CPU-optimized PyTorch (no CUDA)
    && pip install --no-cache-dir "torch>=2.0.0" --index-url https://download.pytorch.org/whl/cpu \
    # Verify installation
    && python -c "import exo; print(f'Exo installed: {exo.__file__}')"

# Verify tinygrad installation and device
RUN python -c "import time; time.sleep(1); import tinygrad; print(f'Tinygrad installed: {tinygrad.__file__}')" \
    # Check tinygrad configuration without using Device class
    && python -c "import os; print(f'CLANG env var: {os.environ.get(\"CLANG\", \"not set\")}'); print(f'CPU env var: {os.environ.get(\"CPU\", \"not set\")}')" \
    # Just import tinygrad and check it works
    && python -c "import tinygrad; print('Tinygrad import successful')"

# Create volume mount points for data
VOLUME ["/data/exo/downloads", "/data/exo/config", "/data/exo/temp"]

# Add a healthcheck
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:52415/v1/chat/completions -X POST \
    -H "Content-Type: application/json" \
    -d '{"model": "llama-3.2-3b", "messages": [{"role": "user", "content": "hello"}], "max_tokens": 1, "temperature": 0}' || exit 1

# Expose ports (used when not running with --net=host)
EXPOSE 52415
EXPOSE 5678/udp

# Setup entrypoint script to handle user permissions
RUN echo '#!/bin/sh\n\
# Setup user with provided UID/GID or use defaults\n\
USER_ID=${PUID:-1000}\n\
GROUP_ID=${PGID:-1000}\n\
\n\
# Set thread count based on environment variables or use defaults\n\
export OMP_NUM_THREADS=${OMP_NUM_THREADS:-4}\n\
export MKL_NUM_THREADS=${MKL_NUM_THREADS:-4}\n\
export OPENBLAS_NUM_THREADS=${OPENBLAS_NUM_THREADS:-4}\n\
export VECLIB_MAXIMUM_THREADS=${VECLIB_MAXIMUM_THREADS:-4}\n\
\n\
# If we are not already running as the correct user\n\
if [ "$(id -u)" != "$USER_ID" ]; then\n\
    # Update existing user/group IDs\n\
    groupmod -g $GROUP_ID exouser\n\
    usermod -u $USER_ID -g $GROUP_ID exouser\n\
\n\
    # Ensure ownership of relevant directories\n\
    chown -R $USER_ID:$GROUP_ID /data/exo\n\
    \n\
    # Drop to the correct user and run the command\n\
    exec gosu exouser "$@"\n\
else\n\
    # Already running as correct user, just execute command\n\
    exec "$@"\n\
fi' > /app/entrypoint.sh && \
    chmod +x /app/entrypoint.sh && \
    # Create user and group
    groupadd -g 1000 exouser && \
    useradd -u 1000 -g exouser -d /home/exouser -m exouser && \
    chown -R exouser:exouser /app /data

# Use the entrypoint script
ENTRYPOINT ["/app/entrypoint.sh"]

# Command to run exo with API focus (Web UI disabled)
CMD ["python", "-m", "exo.main", "--inference-engine", "tinygrad", "--disable-tui"]
