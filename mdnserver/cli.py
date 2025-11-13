"""Command-line interface for mDNServer."""

import logging
import os
import sys
from pathlib import Path
from typing import Optional

import click

from mdnserver.server import MDNServer

# Try to import systemd notification support
SYSTEMD_AVAILABLE = False
notify = None
journal = None

try:
    from systemd import journal  # type: ignore
    from systemd.daemon import notify  # type: ignore

    SYSTEMD_AVAILABLE = True
except ImportError:
    pass


def setup_logging(
    log_level: str, use_systemd: bool = False
) -> None:
    """
    Configure logging for the application.

    Parameters
    ----------
    log_level : str
        Logging level (DEBUG, INFO, WARNING, ERROR).
    use_systemd : bool, optional
        Whether to use systemd journal logging (default: False).

    Notes
    -----
    If systemd is available and use_systemd is True, logs to systemd journal.
    Otherwise, logs to stderr with standard formatting.
    """
    level = getattr(logging, log_level.upper(), logging.INFO)

    if use_systemd and SYSTEMD_AVAILABLE and journal:
        # Use systemd journal handler
        handler = journal.JournalHandler()
        handler.setFormatter(
            logging.Formatter(
                "[%(levelname)s] %(name)s: %(message)s"
            )
        )
        logging.basicConfig(level=level, handlers=[handler])
    else:
        # Standard logging to stderr
        logging.basicConfig(
            level=level,
            format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
            stream=sys.stderr,
        )


def daemonize(pid_file: Optional[str] = None) -> None:
    """
    Daemonize the current process.

    Parameters
    ----------
    pid_file : Optional[str], optional
        Path to write PID file (default: None).

    Notes
    -----
    Forks the process, detaches from terminal, and writes PID file.
    """
    try:
        # First fork
        pid = os.fork()
        if pid > 0:
            # Parent process exits
            sys.exit(0)
    except OSError as e:
        sys.stderr.write(f"Fork #1 failed: {e}\n")
        sys.exit(1)

    # Decouple from parent environment
    os.chdir("/")
    os.setsid()
    os.umask(0)

    try:
        # Second fork
        pid = os.fork()
        if pid > 0:
            # Parent process exits
            sys.exit(0)
    except OSError as e:
        sys.stderr.write(f"Fork #2 failed: {e}\n")
        sys.exit(1)

    # Redirect standard file descriptors
    sys.stdout.flush()
    sys.stderr.flush()
    si = open(os.devnull, "r")
    so = open(os.devnull, "a+")
    se = open(os.devnull, "a+")
    os.dup2(si.fileno(), sys.stdin.fileno())
    os.dup2(so.fileno(), sys.stdout.fileno())
    os.dup2(se.fileno(), sys.stderr.fileno())

    # Write PID file
    if pid_file:
        pid_path = Path(pid_file)
        pid_path.parent.mkdir(parents=True, exist_ok=True)
        with open(pid_path, "w") as f:
            f.write(str(os.getpid()))


@click.command()
@click.option(
    "--port",
    default=5053,
    type=int,
    help="DNS server port (default: 5053).",
)
@click.option(
    "--address",
    default="localhost",
    type=str,
    help="Bind address (default: localhost).",
)
@click.option(
    "--daemon",
    is_flag=True,
    help="Run as daemon (fork to background).",
)
@click.option(
    "--pid-file",
    type=str,
    help="PID file path for daemon mode.",
)
@click.option(
    "--log-level",
    default="INFO",
    type=click.Choice(["DEBUG", "INFO", "WARNING", "ERROR"]),
    help="Logging level (default: INFO).",
)
@click.option(
    "--systemd",
    is_flag=True,
    help="Enable systemd integration (notify and journal logging).",
)
def main(
    port: int,
    address: str,
    daemon: bool,
    pid_file: Optional[str],
    log_level: str,
    systemd: bool,
) -> None:
    """
    mDNServer - DNS server for mDNS resolution via avahi-resolve.

    This server listens for DNS queries and resolves .local domains using
    avahi-resolve, forwarding other queries to 8.8.8.8.
    """
    # Setup logging
    use_systemd_journal = systemd or os.getenv("NOTIFY_SOCKET") is not None
    setup_logging(log_level, use_systemd=use_systemd_journal)

    logger = logging.getLogger(__name__)

    # Daemonize if requested
    if daemon:
        logger.info("Daemonizing process...")
        daemonize(pid_file)
        logger.info("Process daemonized")

    # Notify systemd that we're ready (if running under systemd)
    if SYSTEMD_AVAILABLE and notify:
        if os.getenv("NOTIFY_SOCKET"):
            notify("READY=1")
            logger.info("Notified systemd that service is ready")

    # Create and start server
    try:
        server = MDNServer(port=port, address=address)
        server.start()

        # Wait for shutdown
        server.wait()
    except Exception as e:
        logger.error(f"Server error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()

