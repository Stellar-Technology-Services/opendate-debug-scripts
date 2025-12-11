#!/usr/bin/env python3
"""
PostgreSQL Connection Test Script

Spawns multiple connections to a PostgreSQL database to test RDS proxy behavior.
Connections stay open indefinitely until interrupted.
"""

import os
import sys
import time
import signal
import argparse
import logging
import random
from typing import List, Optional
from dotenv import load_dotenv
import psycopg2

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Global list to store connections
connections: List[psycopg2.extensions.connection] = []
running = True


def signal_handler(sig, frame):
    """Handle graceful shutdown on SIGINT (Ctrl+C)"""
    global running
    logger.info("\nReceived interrupt signal. Closing connections...")
    running = False
    close_all_connections()


def close_all_connections():
    """Close all open connections"""
    logger.info(f"Closing {len(connections)} connections...")
    for i, conn in enumerate(connections):
        try:
            if conn and not conn.closed:
                conn.close()
                logger.info(f"Closed connection {i + 1}")
        except Exception as e:
            logger.error(f"Error closing connection {i + 1}: {e}")
    connections.clear()
    logger.info("All connections closed.")


def get_db_config() -> dict:
    """
    Read database configuration from .env file.
    Supports both DATABASE_URL and separate DB_* variables.
    """
    load_dotenv()
    
    # Try DATABASE_URL first
    database_url = os.getenv('DATABASE_URL')
    if database_url:
        logger.info("Using DATABASE_URL from .env")
        return {'dsn': database_url}
    
    # Fall back to separate variables
    db_config = {
        'host': os.getenv('DB_HOST'),
        'port': os.getenv('DB_PORT', '5432'),
        'database': os.getenv('DB_NAME'),
        'user': os.getenv('DB_USER'),
        'password': os.getenv('DB_PASSWORD'),
    }
    
    # Check if all required fields are present
    required_fields = ['host', 'database', 'user', 'password']
    missing_fields = [field for field in required_fields if not db_config.get(field)]
    
    if missing_fields:
        logger.error(f"Missing required database configuration: {', '.join(missing_fields)}")
        logger.error("Please set either DATABASE_URL or DB_HOST, DB_NAME, DB_USER, DB_PASSWORD in .env file")
        sys.exit(1)
    
    logger.info(f"Using separate DB variables (host: {db_config['host']}, database: {db_config['database']})")
    return db_config


def test_connection(conn: psycopg2.extensions.connection, conn_num: int) -> bool:
    """
    Test a connection by executing a simple query.
    With autocommit enabled, this query will not leave an open transaction.
    """
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
            result = cur.fetchone()
            if result and result[0] == 1:
                logger.info(f"Connection {conn_num}: Test query successful")
                return True
            else:
                logger.warning(f"Connection {conn_num}: Test query returned unexpected result")
                return False
    except Exception as e:
        logger.error(f"Connection {conn_num}: Test query failed - {e}")
        return False


def create_connection(db_config: dict, conn_num: int, init_query: Optional[str] = None) -> Optional[psycopg2.extensions.connection]:
    """
    Create a single database connection
    
    Args:
        db_config: Database configuration dictionary
        conn_num: Connection number for logging
        init_query: Optional SQL query to run after connection (e.g., SET operations)
    """
    try:
        if 'dsn' in db_config:
            conn = psycopg2.connect(db_config['dsn'])
        else:
            conn = psycopg2.connect(
                host=db_config['host'],
                port=db_config['port'],
                database=db_config['database'],
                user=db_config['user'],
                password=db_config['password']
            )
        
        # Enable autocommit to ensure no open transactions
        # This ensures connections show as "idle" not "idle in transaction"
        conn.autocommit = True
        
        # Execute initialization query if provided (e.g., SET operations)
        # Supports multiple statements separated by semicolons
        if init_query:
            try:
                with conn.cursor() as cur:
                    # Split by semicolon and execute each statement
                    statements = [s.strip() for s in init_query.split(';') if s.strip()]
                    for statement in statements:
                        cur.execute(statement)
                logger.info(f"Connection {conn_num}: Executed initialization query: {init_query}")
            except Exception as e:
                logger.error(f"Connection {conn_num}: Failed to execute initialization query '{init_query}': {e}")
                conn.close()
                return None
        
        # Test the connection
        if test_connection(conn, conn_num):
            logger.info(f"Connection {conn_num}: Successfully established (PID: {conn.get_backend_pid()})")
            return conn
        else:
            conn.close()
            return None
            
    except psycopg2.Error as e:
        logger.error(f"Connection {conn_num}: Failed to connect - {e}")
        return None
    except Exception as e:
        logger.error(f"Connection {conn_num}: Unexpected error - {e}")
        return None


def spawn_connections(num_connections: int, db_config: dict, init_query: Optional[str] = None, query_percent: Optional[float] = None):
    """
    Spawn the specified number of connections
    
    Args:
        num_connections: Number of connections to create
        db_config: Database configuration dictionary
        init_query: Optional SQL query to run after each connection (e.g., SET operations)
        query_percent: Optional percentage (0-100) of connections that should run the init_query.
                      If None and init_query is provided, all connections run it.
    """
    logger.info(f"Spawning {num_connections} connections...")
    
    # Determine which connections should get the init query
    connections_with_query = set()
    if init_query:
        if query_percent is not None:
            # Calculate how many connections should get the query
            num_with_query = max(1, int(num_connections * query_percent / 100.0))
            # Randomly select which connections get the query
            connections_with_query = set(random.sample(range(1, num_connections + 1), num_with_query))
            logger.info(f"Initialization query: {init_query}")
            logger.info(f"Query will run on {len(connections_with_query)} out of {num_connections} connections ({query_percent}%)")
        else:
            # All connections get the query
            connections_with_query = set(range(1, num_connections + 1))
            logger.info(f"Initialization query: {init_query}")
            logger.info(f"Query will run on all connections")
    
    successful_connections = 0
    failed_connections = 0
    connections_with_query_count = 0
    connections_without_query_count = 0
    
    for i in range(1, num_connections + 1):
        # Determine if this connection should get the query
        should_run_query = init_query if i in connections_with_query else None
        
        conn = create_connection(db_config, i, should_run_query)
        if conn:
            connections.append(conn)
            successful_connections += 1
            if should_run_query:
                connections_with_query_count += 1
            else:
                connections_without_query_count += 1
        else:
            failed_connections += 1
        
        # Small delay between connections to avoid overwhelming the server
        if i < num_connections:
            time.sleep(0.1)
    
    logger.info(f"\nConnection Summary:")
    logger.info(f"  Successful: {successful_connections}")
    logger.info(f"  Failed: {failed_connections}")
    logger.info(f"  Total open: {len(connections)}")
    if init_query and query_percent is not None:
        logger.info(f"  With init query: {connections_with_query_count}")
        logger.info(f"  Without init query: {connections_without_query_count}")
    
    if len(connections) == 0:
        logger.error("No connections were established. Exiting.")
        sys.exit(1)


def monitor_connections():
    """Monitor connections and log their status periodically"""
    logger.info("\nMonitoring connections. Press Ctrl+C to close all connections and exit.")
    
    check_interval = 30  # Check every 30 seconds
    last_check = time.time()
    
    while running:
        time.sleep(1)
        
        # Periodic status check
        if time.time() - last_check >= check_interval:
            active_connections = sum(1 for conn in connections if conn and not conn.closed)
            logger.info(f"Status check: {active_connections}/{len(connections)} connections still active")
            
            # Test a few random connections with keep-alive queries
            # With autocommit enabled, these queries won't leave open transactions
            if connections:
                test_indices = [0, len(connections) // 2, len(connections) - 1]
                for idx in test_indices:
                    if idx < len(connections):
                        conn = connections[idx]
                        if conn and not conn.closed:
                            try:
                                with conn.cursor() as cur:
                                    cur.execute("SELECT 1")
                            except Exception as e:
                                logger.warning(f"Connection {idx + 1} appears to have issues: {e}")
            
            last_check = time.time()


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='Spawn multiple PostgreSQL connections for RDS proxy testing',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Spawn 10 connections
  python postgres_connection_test.py -n 10

  # Spawn 20 connections with a SET operation
  python postgres_connection_test.py -n 20 -q "SET application_name = 'test_connection'"

  # Set multiple session variables
  python postgres_connection_test.py -n 10 -q "SET timezone = 'UTC'; SET statement_timeout = '5min'"

  # Run query on only 50% of connections
  python postgres_connection_test.py -n 20 -q "SET application_name = 'test'" --query-percent 50
        """
    )
    parser.add_argument(
        '-n', '--num-connections',
        type=int,
        default=10,
        help='Number of connections to spawn (default: 10)'
    )
    parser.add_argument(
        '-q', '--init-query',
        type=str,
        default=None,
        help='SQL query to execute after establishing each connection (e.g., SET operations). '
             'Can include multiple statements separated by semicolons.'
    )
    parser.add_argument(
        '--query-percent',
        type=float,
        default=None,
        metavar='PERCENT',
        help='Percentage (0-100) of connections that should run the init-query. '
             'If not specified and init-query is provided, all connections run it. '
             'Useful for testing mixed connection scenarios.'
    )
    
    args = parser.parse_args()
    
    # Validate query-percent if provided
    if args.query_percent is not None:
        if args.init_query is None:
            logger.error("--query-percent requires --init-query to be specified")
            sys.exit(1)
        if not (0 <= args.query_percent <= 100):
            logger.error("--query-percent must be between 0 and 100")
            sys.exit(1)
    
    # Register signal handler for graceful shutdown
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Load database configuration
    db_config = get_db_config()
    
    # Spawn connections
    spawn_connections(args.num_connections, db_config, args.init_query, args.query_percent)
    
    # Monitor connections
    monitor_connections()


if __name__ == '__main__':
    main()

