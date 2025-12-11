# PostgreSQL Connection Test Script

A Python script to spawn multiple PostgreSQL connections for testing RDS proxy behavior, particularly for troubleshooting connection release issues.

## Features

- Spawns configurable number of connections (default: 10)
- Keeps connections open indefinitely until interrupted
- Supports both `DATABASE_URL` and separate `DB_*` environment variables
- Tests each connection with a simple query
- Monitors connection health periodically
- Graceful shutdown on Ctrl+C

## Setup

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Create a `.env` file based on `.env.example`:
```bash
cp .env.example .env
```

3. Edit `.env` with your database credentials:
   - Either set `DATABASE_URL` with a full connection string
   - Or set `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`

## Local Testing with Docker Compose

For local testing, you can use the included Docker Compose configuration to start a PostgreSQL server:

1. Start the PostgreSQL container:
```bash
docker-compose up -d
```

2. Wait for the database to be ready (check with `docker-compose ps`)

3. Update your `.env` file with the local database credentials:
```
DB_HOST=localhost
DB_PORT=5432
DB_NAME=testdb
DB_USER=testuser
DB_PASSWORD=testpass
```

4. Run the test script as normal

5. Stop the container when done:
```bash
docker-compose down
```

To remove the database volume (clean slate):
```bash
docker-compose down -v
```

### Connecting from WSL

If you're running the test script from WSL (Windows Subsystem for Linux), you have a few options:

**Option 1: Use localhost (if Docker Desktop WSL2 integration is enabled)**
- If Docker Desktop is configured with WSL2 integration, `localhost` should work directly
- Update your `.env`:
```
DB_HOST=localhost
DB_PORT=5432
DB_NAME=testdb
DB_USER=testuser
DB_PASSWORD=testpass
```

**Option 2: Use Windows host IP address**
- Find your Windows host IP from WSL:
```bash
# In WSL, get the Windows host IP
cat /etc/resolv.conf | grep nameserver | awk '{print $2}'
```
- Or use this PowerShell command in Windows:
```powershell
ipconfig | findstr "IPv4"
```
- Update your `.env` with the Windows host IP:
```
DB_HOST=<windows-host-ip>
DB_PORT=5432
DB_NAME=testdb
DB_USER=testuser
DB_PASSWORD=testpass
```

**Option 3: Use host.docker.internal (if available)**
- Some Docker setups support `host.docker.internal`:
```
DB_HOST=host.docker.internal
DB_PORT=5432
DB_NAME=testdb
DB_USER=testuser
DB_PASSWORD=testpass
```

**Testing the connection from WSL:**
```bash
# Test if you can reach the port
nc -zv <host-ip-or-localhost> 5432

# Or use psql if installed
psql -h <host-ip-or-localhost> -p 5432 -U testuser -d testdb
```

### Using psql from WSL

To connect to the PostgreSQL container using `psql` from WSL (while Docker/container runs on Windows):

1. **Install PostgreSQL client in WSL** (if not already installed):
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install postgresql-client

# Or on newer Ubuntu
sudo apt update
sudo apt install postgresql-client
```

2. **Find the Windows host IP** (the IP WSL uses to reach Windows):
```bash
# In WSL, get the Windows host IP
cat /etc/resolv.conf | grep nameserver | awk '{print $2}'
```

3. **Connect using psql**:
```bash
# Replace <windows-host-ip> with the IP from step 2
psql -h <windows-host-ip> -p 5432 -U testuser -d testdb
```

**Example:**
```bash
# If Windows host IP is 172.20.144.1
psql -h 172.20.144.1 -p 5432 -U testuser -d testdb
# Password: testpass
```

**Quick connection test:**
```bash
# Test connection and run a simple query
psql -h <windows-host-ip> -p 5432 -U testuser -d testdb -c "SELECT version();"
```

**Note:** If `localhost` works from Windows PowerShell, you may need to use the Windows host IP from WSL, as WSL and Windows have separate network stacks.

## Usage

Basic usage (10 connections):
```bash
python postgres_connection_test.py
```

Custom number of connections:
```bash
python postgres_connection_test.py -n 20
```

Run initialization query on each connection (e.g., SET operations):
```bash
python postgres_connection_test.py -n 10 -q "SET application_name = 'rds_proxy_test'"
```

Multiple initialization statements:
```bash
python postgres_connection_test.py -n 10 -q "SET timezone = 'UTC'; SET statement_timeout = '5min'"
```

Run initialization query on only a percentage of connections:
```bash
# Run query on 50% of connections (useful for testing mixed scenarios)
python postgres_connection_test.py -n 20 -q "SET application_name = 'test'" --query-percent 50

# Run query on 25% of connections
python postgres_connection_test.py -n 100 -q "SET search_path = 'public'" --query-percent 25
```

**Command-line options:**
- `-n, --num-connections`: Number of connections to spawn (default: 10)
- `-q, --init-query`: SQL query to execute after establishing each connection (e.g., SET operations). Can include multiple statements separated by semicolons.
- `--query-percent`: Percentage (0-100) of connections that should run the init-query. If not specified and init-query is provided, all connections run it. Useful for testing mixed connection scenarios.

The script will:
1. Load database configuration from `.env`
2. Spawn the specified number of connections
3. Execute initialization query on selected connections (if provided and percentage specified, randomly selects which connections get the query)
4. Test each connection
5. Keep connections open and monitor them
6. Log status every 30 seconds
7. Close all connections gracefully on Ctrl+C

## Example Output

```
2024-01-01 12:00:00 - INFO - Using separate DB variables (host: proxy.xxx.us-east-1.rds.amazonaws.com, database: mydb)
2024-01-01 12:00:00 - INFO - Spawning 10 connections...
2024-01-01 12:00:01 - INFO - Connection 1: Test query successful
2024-01-01 12:00:01 - INFO - Connection 1: Successfully established (PID: 12345)
...
2024-01-01 12:00:02 - INFO - Connection Summary:
2024-01-01 12:00:02 - INFO -   Successful: 10
2024-01-01 12:00:02 - INFO -   Failed: 0
2024-01-01 12:00:02 - INFO -   Total open: 10
2024-01-01 12:00:02 - INFO - Monitoring connections. Press Ctrl+C to close all connections and exit.
```

## Troubleshooting

- If connections fail, check your `.env` file has correct credentials
- Ensure your RDS proxy allows connections from your IP
- Check RDS proxy connection limits and current usage
- Monitor RDS proxy metrics while the script is running

