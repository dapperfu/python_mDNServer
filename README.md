# mDNServer

Upstream mDNS lookup server for devices that don't have mDNS.

A Python lDNS server that uses ```avahi-resolve``` to lookup ```.local``` IP addresses. Point ```unbound``` 
 or ```dnsmasq``` to the server to get them to resolve ```.local``` hosts without having to have mDNS on the requesting machine.

## Motivation

1. mDNS is awesome.
1. Not all devices or OSs can use mDNS. 
1. ```unbound``` and ```dnsmasq``` don't allow using 224.0.0.251@5353 as upstream servers for the ```.local``` domain.
  https://superuser.com/questions/821099/configuring-unbound-to-resolve-resolve-on-mdns

## Usage

1. Clone repository.
1. ```make```
1. Point dnsmasq at 127.0.0.1:5053 for the local domain:
     `server=/local/127.0.0.1#5053`
     
## TODO
 
1. ```systemd```
 
## Test

- ```make test``` - Uses ```hostname```.
- ```make test HOST=apt-cacher-ng.local```