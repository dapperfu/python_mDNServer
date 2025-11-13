CWD = $(realpath $(dir $(firstword $(MAKEFILE_LIST))))
VENV = ${CWD}/venv_python_mDNServer
PIP = ${VENV}/bin/pip
PYTHON = ${VENV}/bin/python

BASE = setuptools wheel build

# Virtual environment target
${VENV}: pyproject.toml
	python3 -mvenv ${VENV}
	${PIP} install --upgrade pip
	${PIP} install --upgrade ${BASE}
	${PIP} install -e ".[dev]"

.PHONY: install
install: ${VENV}
	@echo "Package installed in development mode"

.PHONY: server
server: ${VENV}
	${PYTHON} -m mdnserver.cli

.PHONY: build
build: ${VENV}
	${PYTHON} -m build

.PHONY: clean
clean:
	git clean -xfd
	rm -rf ${VENV}
	rm -rf build/
	rm -rf dist/
	rm -rf *.egg-info/

.PHONY: test
HOST ?= $(shell hostname).local
test:
	@echo Testing Host: ${HOST}
	@echo
	@echo Testing avahi-resolve:
	avahi-resolve --name -4 ${HOST}
	@echo
	@echo Testing dig with multicast:
	dig @224.0.0.251 -p 5353 +short A ${HOST}
	@echo
	@echo Testing mdnserver:
	dig @127.0.0.1 -p 5053 +short A ${HOST}
	@echo
	@echo Working correctly all of the above methods should resolve to the same IP.

.PHONY: docker-build
docker-build:
	docker build -t mdnserver:latest .

.PHONY: docker-run
docker-run:
	docker run -d --network host --name mdnserver mdnserver:latest

.PHONY: docker-stop
docker-stop:
	docker stop mdnserver || true
	docker rm mdnserver || true

.PHONY: docker-compose-up
docker-compose-up:
	docker-compose up -d

.PHONY: docker-compose-down
docker-compose-down:
	docker-compose down

.PHONY: typecheck
typecheck: ${VENV}
	${VENV}/bin/mypy mdnserver/

.PHONY: format
format: ${VENV}
	${VENV}/bin/black mdnserver/

.PHONY: lint
lint: ${VENV}
	${VENV}/bin/ruff check mdnserver/
