"""DNS server implementation for mDNS resolution via avahi-resolve."""

import logging
import signal
import subprocess
import sys
import time
from typing import Optional

from dnslib import QTYPE, RR, dns
from dnslib.proxy import ProxyResolver
from dnslib.server import DNSServer, DNSHandler, DNSRecord

logger = logging.getLogger(__name__)


class Resolver(ProxyResolver):
    """
    DNS resolver that uses avahi-resolve for .local domains.

    This resolver handles DNS queries by:
    - Using avahi-resolve for .local domain queries
    - Falling back to 8.8.8.8 for non-.local domains
    - Supporting both A (IPv4) and AAAA (IPv6) record types

    Parameters
    ----------
    None

    Attributes
    ----------
    None

    Notes
    -----
    Inherits from ProxyResolver but overrides __init__ to avoid calling
    the parent class constructor.

    Examples
    --------
    >>> resolver = Resolver()
    >>> reply = resolver.resolve(request, handler)
    """

    def __init__(self) -> None:
        """
        Initialize the resolver.

        Do nothing init, but defined so it doesn't call the super class'
        constructor.
        """
        pass

    def resolve(
        self, request: DNSRecord, handler: DNSHandler
    ) -> DNSRecord:
        """
        Resolve a DNS request.

        Parameters
        ----------
        request : DNSRecord
            The DNS request to resolve.
        handler : DNSHandler
            The DNS handler instance.

        Returns
        -------
        DNSRecord
            The DNS reply with answers if available.

        Notes
        -----
        For .local domains, uses avahi-resolve. For other domains,
        forwards to 8.8.8.8.
        """
        # Build a request reply.
        reply = request.reply()

        # Determine address type and IP class based on query type.
        if request.q.qtype == QTYPE.A:
            addr = "-4"
            ip_cls = dns.A  # Class to wrap the ip string with.
        elif request.q.qtype == QTYPE.AAAA:
            addr = "-6"
            ip_cls = dns.AAAA  # Class to wrap the ip string with.
        else:
            # Return nothing for unsupported query types.
            logger.debug(f"Unsupported query type: {request.q.qtype}")
            return reply

        # Strip trailing period.
        host = str(request.q.qname).rstrip(".")

        # If not a .local domain, forward to 8.8.8.8.
        if not host.endswith(".local"):
            logger.debug(f"Forwarding non-local query for {host} to 8.8.8.8")
            try:
                a = DNSRecord.parse(
                    DNSRecord.question(host).send("8.8.8.8", 53)
                )
                for rr in a.rr:
                    if rr.rtype == request.q.qtype:
                        reply.add_answer(rr)
                return reply
            except Exception as e:
                logger.error(f"Error forwarding query to 8.8.8.8: {e}")
                return reply

        # Use avahi-resolve for .local domains.
        try:
            logger.debug(f"Resolving .local host: {host} with avahi-resolve")
            # Use avahi-resolve to determine the .local host IP address.
            result = subprocess.check_output(
                ["avahi-resolve", "--name", addr, host], timeout=1
            )
            # Parse output.
            [host, ip] = result.decode("UTF-8").strip("\n").split("\t")
            logger.info(f"Resolved {host} to {ip}")
            # Build a result and add the answer to the reply.
            rr = RR(
                rname=request.q.qname,
                rtype=request.q.qtype,
                rdata=ip_cls(ip),
                ttl=300,
            )
            reply.add_answer(rr)
        except subprocess.TimeoutExpired:
            # Time out == host not found.
            logger.debug(f"Timeout resolving {host} - host not found")
            pass
        except Exception as e:
            logger.error(f"Error resolving {host}: {e}")
            raise
        # Return the reply.
        return reply


class MDNServer:
    """
    mDNS server that listens for DNS queries.

    Parameters
    ----------
    port : int, optional
        Port to listen on (default: 5053).
    address : str, optional
        Address to bind to (default: 'localhost').
    resolver : Optional[Resolver], optional
        Custom resolver instance (default: None, creates new Resolver).

    Attributes
    ----------
    port : int
        Port the server listens on.
    address : str
        Address the server binds to.
    resolver : Resolver
        The DNS resolver instance.
    servers : list[DNSServer]
        List of DNS server instances (TCP and UDP).

    Examples
    --------
    >>> server = MDNServer(port=5053, address='localhost')
    >>> server.start()
    >>> server.wait()
    >>> server.stop()
    """

    def __init__(
        self,
        port: int = 5053,
        address: str = "localhost",
        resolver: Optional[Resolver] = None,
    ) -> None:
        """
        Initialize the mDNS server.

        Parameters
        ----------
        port : int, optional
            Port to listen on (default: 5053).
        address : str, optional
            Address to bind to (default: 'localhost').
        resolver : Optional[Resolver], optional
            Custom resolver instance (default: None, creates new Resolver).
        """
        self.port = port
        self.address = address
        self.resolver = resolver if resolver is not None else Resolver()

        # Create a local server on specified port listening on TCP and UDP.
        self.servers = [
            DNSServer(
                resolver=self.resolver, port=port, address=address, tcp=True
            ),
            DNSServer(
                resolver=self.resolver, port=port, address=address, tcp=False
            ),
        ]

        # Setup signal handlers for graceful shutdown.
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGHUP, self._signal_handler)

        self._running = False

    def _signal_handler(
        self, signum: int, frame: Optional[object]
    ) -> None:
        """
        Handle system signals for graceful shutdown.

        Parameters
        ----------
        signum : int
            Signal number.
        frame : Optional[object]
            Current stack frame.
        """
        logger.info(f"Received signal {signum}, shutting down...")
        self.stop()

    def start(self) -> None:
        """
        Start the DNS servers.

        Notes
        -----
        Starts both TCP and UDP servers in separate threads.
        """
        logger.info(
            f"Starting mDNS server on {self.address}:{self.port} "
            "(TCP and UDP)"
        )
        for s in self.servers:
            s.start_thread()
        self._running = True

    def stop(self) -> None:
        """
        Stop the DNS servers.

        Notes
        -----
        Stops all running server threads gracefully.
        """
        if self._running:
            logger.info("Stopping mDNS server...")
            for s in self.servers:
                s.stop()
            self._running = False
            logger.info("mDNS server stopped")

    def wait(self) -> None:
        """
        Wait for the server to run until interrupted.

        Notes
        -----
        Blocks until a signal is received or KeyboardInterrupt.
        Periodically flushes stdout/stderr for systemd compatibility.
        """
        try:
            while self._running:
                # Twiddle thumbs.
                time.sleep(1)
                sys.stdout.flush()
                sys.stderr.flush()
        except KeyboardInterrupt:
            logger.info("Keyboard interrupt received")
        finally:
            self.stop()

