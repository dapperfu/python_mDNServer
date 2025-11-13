# mDNServer

Upstream mDNS lookup server for devices that don't have mDNS.

A Python DNS server that uses `avahi-resolve` to lookup `.local` IP addresses. Point `unbound` 
or `dnsmasq` to the server to get them to resolve `.local` hosts without having to have mDNS on the requesting machine.

## Motivation

1. mDNS is awesome.
2. Not all devices or OSs can use mDNS.
3. `unbound` and `dnsmasq` don't allow using 224.0.0.251@5353 as upstream servers for the `.local` domain.
   https://superuser.com/questions/821099/configuring-unbound-to-resolve-resolve-on-mdns

## Installation

### From Source

```bash
# Clone repository
git clone https://github.com/jedfrey/python_mDNServer.git
cd python_mDNServer

# Install in development mode
pip install -e .

# Or install in production mode
pip install .
```

### Using pip

```bash
pip install mdnserver
```

## Usage

### Command Line

```bash
# Basic usage (default: localhost:5053)
mdnserver

# Custom port and address
mdnserver --port 5353 --address 0.0.0.0

# Run as daemon
mdnserver --daemon --pid-file /var/run/mdnserver.pid

# With systemd integration
mdnserver --systemd --log-level INFO

# All options
mdnserver --help
```

### Configuration Options

- `--port`: DNS server port (default: 5053)
- `--address`: Bind address (default: localhost)
- `--daemon`: Run as daemon (fork to background)
- `--pid-file`: PID file path for daemon mode
- `--log-level`: Logging level: DEBUG, INFO, WARNING, ERROR (default: INFO)
- `--systemd`: Enable systemd integration (notify and journal logging)

### Point dnsmasq/unbound to mdnserver

For dnsmasq, add to `/etc/dnsmasq.conf`:
```
server=/local/127.0.0.1#5053
```

For unbound, add to `/etc/unbound/unbound.conf`:
```
forward-zone:
    name: "local"
    forward-addr: 127.0.0.1@5053
```

## Systemd Integration

### Installation

1. Copy the systemd service file:
   ```bash
   sudo cp contrib/mdnserver.service /etc/systemd/system/
   ```

2. Create user and group (if needed):
   ```bash
   sudo useradd -r -s /bin/false mdnserver
   ```

3. Edit `/etc/systemd/system/mdnserver.service` to adjust settings:
   - Port, address, log level
   - User/group
   - PID file location

4. Enable and start the service:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable mdnserver
   sudo systemctl start mdnserver
   ```

5. Check status:
   ```bash
   sudo systemctl status mdnserver
   sudo journalctl -u mdnserver -f
   ```

## Docker

### Build Image

```bash
docker build -t mdnserver:latest .
```

### Run Container

```bash
# Using host network (recommended for mDNS access)
docker run -d --network host --name mdnserver mdnserver:latest

# Or with port mapping (bridge network)
docker run -d -p 5053:5053/udp -p 5053:5053/tcp --name mdnserver mdnserver:latest
```

### Docker Compose

```bash
# Start services
docker-compose up -d

# View logs
docker-compose logs -f mdnserver

# Stop services
docker-compose down
```

The `docker-compose.yml` file includes:
- mdnserver service with host network mode
- Health checks
- Automatic restart policy
- Example configuration for integration with dnsmasq

## Development

### Setup Development Environment

```bash
# Create virtual environment
python3 -m venv venv_python_mDNServer
source venv_python_mDNServer/bin/activate

# Install in development mode with dev dependencies
pip install -e ".[dev]"
```

### Running Tests

```bash
# Using make
make test

# With custom host
make test HOST=apt-cacher-ng.local

# Using pytest directly
pytest
```

### Code Quality

```bash
# Type checking
mypy mdnserver/

# Formatting
black mdnserver/

# Linting
ruff check mdnserver/
```

## How It Works

1. The server listens for DNS queries on the specified port (default 5053)
2. For `.local` domains, it uses `avahi-resolve` to resolve the mDNS name
3. For other domains, it forwards queries to 8.8.8.8
4. Supports both A (IPv4) and AAAA (IPv6) record types

## Requirements

- Python 3.8+
- avahi-utils (for `avahi-resolve` command)
- dnslib Python package
- click Python package

## Test

```bash
# Test with default hostname
make test

# Test with specific host
make test HOST=apt-cacher-ng.local
```

The test verifies that:
- `avahi-resolve` can resolve the host
- Multicast DNS (224.0.0.251:5353) can resolve the host
- mdnserver can resolve the host

All three methods should return the same IP address.

## License

BSD 3-Clause License

## Credits

Based on [dnsserver.py](https://github.com/samuelcolvin/dnserver/blob/master/dnserver.py)
