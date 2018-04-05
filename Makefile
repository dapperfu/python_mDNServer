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
