CWD = $(realpath $(dir $(firstword $(MAKEFILE_LIST))))
PIP?=${CWD}/bin/pip
PYTHON?=${CWD}/bin/python

BASE?=setuptools wheel

.PHONY: server
server: pyvenv.cfg
	${PYTHON} mdnserver.py

pyvenv.cfg: requirements.txt
	python3 -mvenv ${CWD}
	${PIP} install --upgrade pip
	${PIP} install --upgrade ${BASE}
	${PIP} install -r requirements.txt

.PHONY: clean
clean:
	git clean -xfd

HOST?=$(shell hostname).local
.PHONY: test
test:
	@echo Testing Host: ${HOST}
	@echo
	@echo Testing avahi-resolve:
	avahi-resolve --name -4 ${HOST}
	@echo
	@echo Testing dig with multicast:
	dig @224.0.0.251 -p 5353 +short A ${HOST}
	@echo
	@echo Testing mdnserver.py
	dig @127.0.0.1 -p 5053 +short A ${HOST}
	@echo
	@echo Working correctly all of the above methods should resolve to the same IP.

