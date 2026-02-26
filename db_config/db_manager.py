from psycopg2.pool import SimpleConnectionPool
from psycopg2.extras import RealDictCursor
from psycopg2 import Error
from functools import wraps
import atexit
import signal
import sys

import logging

logger = logging.getLogger(__name__)


class DatabaseManager:
    def __init__(self, config):
        """Initialize the connection pool using configuration settings."""
        self.config = config
        self._init_pool()
        atexit.register(self.close_pool)
        signal.signal(signal.SIGTERM, self._handle_signal)
        signal.signal(signal.SIGINT, self._handle_signal)

    def _handle_signal(self, signum, frame):
        self.close_pool()
        sys.exit(1)

    def _init_pool(self):
        self.pool = SimpleConnectionPool(
            self.config["minconn"],
            self.config["maxconn"],
            host=self.config["host"],
            database=self.config["database"],
            user=self.config["user"],
            password=self.config["password"],
            port=self.config["port"],
            gssencmode="disable",
        )

    def get_pool(self):
        if self.pool.closed:
            self._init_pool()
        return self.pool

    def with_db_cursor(self, func):
        """Decorator to manage database connections and cursors."""

        @wraps(func)
        def wrapper(*args, **kwargs):
            conn = self.get_pool().getconn()  # Get a connection from the pool
            try:
                with conn.cursor(cursor_factory=RealDictCursor) as cur:
                    result = func(cur, *args, **kwargs)
                    conn.commit()
                    return result
            except Error as e:  # Catch psycopg2 errors specifically
                conn.rollback()

                # Print full PostgreSQL error details
                print("PostgreSQL Error Details:")
                print(f"SQLSTATE: {e.pgcode}")  # SQLSTATE error code
                print(f"Message: {e.pgerror}")  # Full error message

                # Log the error details
                logger.error(
                    f"PostgreSQL Error occurred: SQLSTATE: {e.pgcode}, Message: {e.pgerror}"
                )

                # Re-raise the error to ensure it's handled by the calling function
                raise e
            finally:
                self.pool.putconn(conn)  # Always return the connection to the pool

        return wrapper

    def close_pool(self):
        """Close all connections in the pool."""
        if self.pool and not self.pool.closed:
            self.pool.closeall()

    # context manager support
    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close_pool()
