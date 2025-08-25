# SSH Tunnel Docker Container

A lightweight Docker container for creating SSH tunnels with local and remote port forwarding. Perfect for securely accessing remote services or exposing local services through SSH.

## Features

- 🔒 Secure SSH tunneling with private key authentication
- 🌐 Configurable local and remote port forwarding
- 📊 Built-in health checks
- 🔄 Automatic reconnection with keep-alive
- 🐳 Docker and Docker Compose ready
- 📝 Comprehensive logging

## Quick Start

### 1. Build the Container

```bash
docker build -f Dockerfile -t ssh-tunnel .
```

### 2. Run with Docker

```bash
# Local forwarding example
docker run -d \
  --name ssh-tunnel-local \
  -e SSH_HOST=your-server.com \
  -e SSH_USER=your-username \
  -e SSH_LOCAL_FORWARD=3306:localhost:3306 \
  -v /path/to/your/private/key:/ssh-keys/id_rsa:ro \
  -p 3306:3306 \
  ssh-tunnel

# Remote forwarding example
docker run -d \
  --name ssh-tunnel-remote \
  -e SSH_HOST=your-server.com \
  -e SSH_USER=your-username \
  -e SSH_REMOTE_FORWARD=8080:internal-app:3000 \
  -v /path/to/your/private/key:/ssh-keys/id_rsa:ro \
  ssh-tunnel
```

### 3. Run with Docker Compose

```bash
# Edit docker-compose.yml with your settings
docker-compose -f docker-compose.yml up -d
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SSH_HOST` | ✅ | - | Target SSH server hostname or IP |
| `SSH_USER` | ❌ | root | SSH username for authentication |
| `SSH_PORT` | ❌ | 22 | SSH server port |
| `SSH_LOCAL_FORWARD` | ❌ | - | Local port forwarding spec: `[bind_address:]local_port:remote_host:remote_port` |
| `SSH_REMOTE_FORWARD` | ❌ | - | Remote port forwarding spec: `[bind_address:]remote_port:local_host:local_port` |
| `SSH_OPTIONS` | ❌ | - | Additional SSH client options |

## Port Forwarding Examples

### Local Forwarding
Local forwarding allows you to access remote services through the tunnel by forwarding local ports to remote destinations.

The format supports an optional bind address:
- `local_port:remote_host:remote_port` - Binds to all interfaces (0.0.0.0) by default
- `bind_address:local_port:remote_host:remote_port` - Binds to specific address

**Security Note**: 
- Default binding is `0.0.0.0` (all interfaces) for Docker container accessibility
- Use `127.0.0.1` to restrict access to localhost only
- Use specific IP addresses to restrict access to particular networks

### Database Tunnels
```bash
# MySQL/MariaDB (default: bind to all interfaces)
SSH_LOCAL_FORWARD=3306:localhost:3306

# PostgreSQL (explicit localhost binding for security)
SSH_LOCAL_FORWARD=127.0.0.1:5432:localhost:5432

# Redis (explicit all interfaces binding - same as default)
SSH_LOCAL_FORWARD=0.0.0.0:6379:localhost:6379

# MongoDB (bind to specific interface)
SSH_LOCAL_FORWARD=192.168.1.100:27017:localhost:27017
```

### Web Services
```bash
# Internal web service (default: bind to all interfaces)
SSH_LOCAL_FORWARD=8080:internal-app:80

# Admin panel (explicit localhost binding for security)
SSH_LOCAL_FORWARD=127.0.0.1:9000:admin.internal:443

# Public service (explicit all interfaces binding - same as default)
SSH_LOCAL_FORWARD=0.0.0.0:3000:web-server:3000
```

### Remote Forwarding
Remote forwarding allows you to expose local services to the remote server through the tunnel.

```bash
# Expose local web app to remote server
SSH_REMOTE_FORWARD=8080:internal-app:3000

# Expose local database to remote server  
SSH_REMOTE_FORWARD=5432:internal-db:5432

# Expose local service to specific remote interface
SSH_REMOTE_FORWARD=9000:192.168.1.100:8080
```

### Multiple Ports
For multiple port forwards, run multiple containers or use SSH_OPTIONS:
```bash
# Multiple local forwards with different bind addresses
SSH_OPTIONS="-L 127.0.0.1:5432:localhost:5432 -L 0.0.0.0:6379:localhost:6379"

# Multiple remote forwards
SSH_OPTIONS="-R 8080:internal-app:3000 -R 9000:internal-app:4000"

# Mixed local and remote forwards
SSH_OPTIONS="-L 127.0.0.1:3306:localhost:3306 -R 8080:internal-app:3000"
```

### Combined Forwarding
You can use both local and remote forwarding in the same tunnel:
```bash
docker run -d \
  -e SSH_HOST=your-server.com \
  -e SSH_USER=your-username \
  -e SSH_LOCAL_FORWARD=3306:localhost:3306 \
  -e SSH_REMOTE_FORWARD=8080:internal-app:3000 \
  -v /path/to/key:/ssh-keys/id_rsa:ro \
  -p 3306:3306 \
  ssh-tunnel
```

## Volume Mounts

| Path | Required | Description |
|------|----------|-------------|
| `/ssh-keys/id_rsa` | ✅ | Private SSH key file (mounted as read-only) |

## Port Exposure

The container exposes common ports by default:
- 3306 (MySQL)
- 5432 (PostgreSQL) 
- 6379 (Redis)
- 8080 (HTTP)
- 9000 (Admin)

You can map any port using `-p host_port:container_port`.

## SSH Key Setup

### Generate SSH Key Pair (if needed)
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/tunnel_key
```

### Copy Public Key to Target Server
```bash
ssh-copy-id -i ~/.ssh/tunnel_key.pub user@your-server.com
```

### Mount SSH Key in Docker

```bash
# Mount to /ssh-keys/id_rsa
-v ~/.ssh/tunnel_key:/ssh-keys/id_rsa:ro
```

**Benefits of this approach:**
- Container copies the key with proper permissions (600)
- Avoids permission errors when using read-only bind mounts
- Works with any file system permissions on the host
- Clean separation between mounted files and working files

## Health Checks

The container includes automatic health checks that verify the tunnel is working by testing the local port connectivity.

```bash
# Check container health
docker ps

# View health check logs
docker inspect ssh-tunnel | grep Health -A 10
```

## Monitoring and Logs

```bash
# View tunnel logs
docker logs ssh-tunnel

# Follow logs in real-time
docker logs -f ssh-tunnel

# Check if tunnel is active
docker exec ssh-tunnel netstat -tlnp | grep :3306
```

## Troubleshooting

### Common Issues

1. **Missing Forwarding Configuration**
   ```
   ERROR: At least one of SSH_LOCAL_FORWARD, SSH_REMOTE_FORWARD, or SSH_OPTIONS must be specified
   ```
   - Ensure at least one forwarding type is configured
   - Check environment variable names are correct
   - This container requires forwarding configuration to function

2. **Private Key Not Found**
   ```
   ERROR: Private key not found at /ssh-keys/id_rsa
   ```
   - Verify the volume mount path: `-v /path/to/key:/ssh-keys/id_rsa:ro`
   - Check that the private key file exists on the host

3. **Tunnel Dies Unexpectedly**
   ```bash
   # Check SSH server logs
   docker logs ssh-tunnel

   # Verify network connectivity
   docker exec ssh-tunnel ping your-server.com
   ```

### Debug Mode

Run with verbose SSH logging:
```bash
# Debug local forwarding (default: bind to all interfaces)
docker run -it \
  -e SSH_HOST=your-server.com \
  -e SSH_USER=your-username \
  -e SSH_LOCAL_FORWARD=3306:localhost:3306 \
  -e SSH_OPTIONS="-vvv" \
  -v /path/to/key:/ssh-keys/id_rsa:ro \
  ssh-tunnel

# Debug local forwarding (explicit bind to all interfaces)
docker run -it \
  -e SSH_HOST=your-server.com \
  -e SSH_USER=your-username \
  -e SSH_LOCAL_FORWARD=0.0.0.0:8080:internal-service:80 \
  -e SSH_OPTIONS="-vvv" \
  -v /path/to/key:/ssh-keys/id_rsa:ro \
  ssh-tunnel

# Debug remote forwarding
docker run -it \
  -e SSH_HOST=your-server.com \
  -e SSH_USER=your-username \
  -e SSH_REMOTE_FORWARD=8080:internal-app:3000 \
  -e SSH_OPTIONS="-vvv" \
  -v /path/to/key:/ssh-keys/id_rsa:ro \
  ssh-tunnel
```

## Security Considerations

- Always use read-only mounts for private keys
- Keep private keys secure and never commit them to version control
- Use strong SSH key passphrases (not supported in this container)
- Consider using SSH certificates instead of keys for enterprise environments
- Regularly rotate SSH keys
- **Private Key Handling**: The container copies the private key to `/root/.ssh/id_rsa` with proper permissions (600). The key remains in the container to handle SSH reconnections during network interruptions or keep-alive failures

## Production Recommendations

1. **Resource Limits**
   ```yaml
   services:
     ssh-tunnel:
       deploy:
         resources:
           limits:
             memory: 64M
             cpus: 0.1
   ```

2. **Restart Policy**
   ```yaml
   restart: unless-stopped
   ```

3. **Health Checks**
   ```yaml
   healthcheck:
     test: ["CMD", "nc", "-z", "localhost", "3306"]
     interval: 30s
     timeout: 10s
     retries: 3
   ```

4. **Logging**
   ```yaml
   logging:
     driver: "json-file"
     options:
       max-size: "10m"
       max-file: "3"
   ```

## Examples

See `docker-compose.yml` for a complete example with database access through SSH tunnel.
