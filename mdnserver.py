#!/usr/bin/env python
import subprocess
import sys
from time import sleep

from dnslib import QTYPE, RR, dns
from dnslib.proxy import ProxyResolver
from dnslib.server import DNSServer
from dnslib.server import DNSRecord

class Resolver(ProxyResolver):
    # Do nothing init, but defined so it doesn't call the super class'
    def __init__(self):
        pass

    # Resolve
    def resolve(self, request, handler):
        # Build a request reply.
        reply = request.reply()
        # If it is of type A, IPv4:
        if request.q.qtype == QTYPE.A:
            addr = "-4"
            ip_cls = dns.A  # Class to wrap the ip string with.
        # If it is of type AAAA, IPv6:
        elif request.q.qtype == QTYPE.AAAA:
            addr = "-6"
            ip_cls = dns.AAAA  # Class to wrap the ip string with.
        else:
            # Return nothing.
            return reply

        # Strip trailing period.
        host = str(request.q.qname).rstrip(".")
        
        if not host.endswith(".local"):
            a = DNSRecord.parse(DNSRecord.question(host).send("8.8.8.8", 53))
            for rr in a.rr:
                if rr.rtype == request.q.qtype:
                    reply.add_answer(rr)
            return reply

        try:
            # Use avahi-resolve to determine the .local host IP address.
            result = subprocess.check_output(
                ["avahi-resolve", "--name", addr, host], timeout=1)
            # Parse output.
            [host, ip] = result.decode("UTF-8").strip("\n").split("\t")
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
            pass
        except BaseException:
            raise
        # Return the reply.
        return reply


# Get a resolver instance
resolver = Resolver()
# Create a local server on port 5053 listening on TCP and UDP.
servers = [
    DNSServer(resolver=resolver, port=5053, address='localhost', tcp=True),
    DNSServer(resolver=resolver, port=5053, address='localhost', tcp=False),
]

# If this file is called
if __name__ == '__main__':
    for s in servers:
        s.start_thread()
    try:
        while True:
            # Twiddle thumbs.
            sleep(10)
            # Flush stderr and stdout.
            sys.stderr.flush()
            sys.stdout.flush()
    except KeyboardInterrupt:
        pass
    finally:
        for s in servers:
            s.stop()
