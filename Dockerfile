# SSH Tunnel Dockerfile
# Creates a lightweight container for establishing SSH tunnels
#
# Environment Variables:
#   SSH_HOST - Target SSH host (required)
#   SSH_USER - SSH user (default: root)
#   SSH_PORT - SSH port (default: 22)
#   SSH_LOCAL_FORWARD - Local forwarding specification (optional)
#       Format: "[bind_address:]local_port:remote_host:remote_port"
#       Examples: "3306:localhost:3306"
#       By default, it will bind to all interfaces (0.0.0.0), unless bind_address is specified
#   SSH_REMOTE_FORWARD - Remote forwarding specification (optional)
#       Format: "[bind_address:]remote_port:local_host:local_port"
#       Examples: "8080:internal-app:3000"
#       By default, it will bind to localhost on the remote server, unless bind_address is specified
#   SSH_OPTIONS - Additional SSH options (optional)
#
# Volume Mount:
#   /ssh-keys/id_rsa - Private key file (required, mounted as read-only)
#
# Usage Example:
#   docker build -f Dockerfile -t ssh-tunnel .
#   docker run -d \
#     -e SSH_HOST=example.com \
#     -e SSH_USER=myuser \
#     -e SSH_LOCAL_FORWARD=3306:localhost:3306 \
#     -v /path/to/private/key:/ssh-keys/id_rsa:ro \
#     -p 3306:3306 \
#     ssh-tunnel
#
#   # Remote forwarding example:
#   docker run -d \
#     -e SSH_HOST=example.com \
#     -e SSH_USER=myuser \
#     -e SSH_REMOTE_FORWARD=8080:internal-app:3000 \
#     -v /path/to/private/key:/ssh-keys/id_rsa:ro \
#     ssh-tunnel

FROM alpine:3.22

# Install OpenSSH client and required tools
RUN apk add --no-cache \
    openssh-client \
    bash \
    curl \
    netcat-openbsd \
    && rm -rf /var/cache/apk/*

# Create SSH directory and set proper permissions
RUN mkdir -p /ssh-keys /root/.ssh && chmod 700 /root/.ssh

# Create entrypoint script
COPY <<EOF /entrypoint.sh
#!/bin/bash

set -e

# Validate required environment variables
if [ -z "\$SSH_HOST" ]; then
    echo "ERROR: SSH_HOST environment variable is required"
    exit 1
fi

# Validate that at least one forwarding type is specified
if [ -z "\$SSH_LOCAL_FORWARD" ] && [ -z "\$SSH_REMOTE_FORWARD" ] && [ -z "\$SSH_OPTIONS" ]; then
    echo "ERROR: At least one of SSH_LOCAL_FORWARD, SSH_REMOTE_FORWARD, or SSH_OPTIONS must be specified"
    echo "This container is designed for SSH tunneling - forwarding configuration is required"
    exit 1
fi

# Check for private key in mounted directory
if [ ! -f "/ssh-keys/id_rsa" ]; then
    echo "ERROR: Private key not found at /ssh-keys/id_rsa"
    echo "Please mount your private key file to /ssh-keys/id_rsa"
    exit 1
fi

# Set default SSH user if not provided
SSH_USER=\${SSH_USER:-root}

# Set default SSH port if not provided
SSH_PORT=\${SSH_PORT:-22}

# Copy private key to /root/.ssh/id_rsa and set permissions
cp /ssh-keys/id_rsa /root/.ssh/id_rsa
chmod 600 /root/.ssh/id_rsa

# Build SSH command
SSH_CMD="ssh -N -T"
SSH_CMD="\$SSH_CMD -o StrictHostKeyChecking=no"
SSH_CMD="\$SSH_CMD -o ServerAliveInterval=60"
SSH_CMD="\$SSH_CMD -o ServerAliveCountMax=3"
SSH_CMD="\$SSH_CMD -o ExitOnForwardFailure=yes"

# Add custom SSH options if provided
if [ -n "\$SSH_OPTIONS" ]; then
    SSH_CMD="\$SSH_CMD \$SSH_OPTIONS"
fi

# Add port forwarding
if [ -n "\$SSH_LOCAL_FORWARD" ]; then
    # If no bind address is specified, default to bind to all interfaces (0.0.0.0)
    if [[ "\$SSH_LOCAL_FORWARD" != *:*:*:* ]]; then
        SSH_LOCAL_FORWARD="0.0.0.0:\$SSH_LOCAL_FORWARD"
    fi
    SSH_CMD="\$SSH_CMD -L \$SSH_LOCAL_FORWARD"
fi

if [ -n "\$SSH_REMOTE_FORWARD" ]; then
    SSH_CMD="\$SSH_CMD -R \$SSH_REMOTE_FORWARD"
fi

# Add connection details
SSH_CMD="\$SSH_CMD -p \$SSH_PORT \$SSH_USER@\$SSH_HOST"

echo "Starting SSH tunnel..."
if [ -n "\$SSH_LOCAL_FORWARD" ]; then
    echo "Local forwarding: \$SSH_LOCAL_FORWARD"
fi
if [ -n "\$SSH_REMOTE_FORWARD" ]; then
    echo "Remote forwarding: \$SSH_REMOTE_FORWARD"
fi
echo "SSH Host: \$SSH_HOST:\$SSH_PORT"
echo "SSH User: \$SSH_USER"

# Function to handle shutdown gracefully
cleanup() {
    echo "Shutting down SSH tunnel..."
    kill -TERM \$SSH_PID 2>/dev/null || true
    wait \$SSH_PID 2>/dev/null || true
    echo "SSH tunnel stopped"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Start SSH tunnel in background and capture PID
eval "\$SSH_CMD" &
SSH_PID=\$!

echo "SSH tunnel established (PID: \$SSH_PID)"
echo "Tunnel is ready!"

# Health check function
health_check() {
    # Only perform health check if local forwarding is enabled
    if [ -n "\$SSH_LOCAL_FORWARD" ]; then
        # Extract local port correctly - after preprocessing, format is always bind_address:local_port:remote_host:remote_port
        local local_port=\$(echo "\$SSH_LOCAL_FORWARD" | cut -d':' -f2)
        if command -v nc >/dev/null 2>&1; then
            nc -z localhost "\$local_port" >/dev/null 2>&1
        else
            # Fallback using /dev/tcp
            timeout 1 bash -c "</dev/tcp/localhost/\$local_port" >/dev/null 2>&1
        fi
    else
        # For remote forwarding only, just check if SSH process is alive
        return 0
    fi
}

# Monitor tunnel and perform health checks
while kill -0 \$SSH_PID 2>/dev/null; do
    sleep 30
    if ! health_check; then
        echo "WARNING: Health check failed - tunnel may be down"
    fi
done

echo "SSH process terminated unexpectedly"
exit 1
EOF

# Make entrypoint script executable
RUN chmod +x /entrypoint.sh

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD /bin/bash -c 'if [ -n "$SSH_LOCAL_FORWARD" ]; then local_port=$(echo "$SSH_LOCAL_FORWARD" | cut -d":" -f2); nc -z localhost $local_port; else exit 0; fi'

# Expose common ports (can be overridden)
EXPOSE 3306 5432 6379 8080 9000

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
