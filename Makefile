CWD = $(realpath $(dir $(firstword $(MAKEFILE_LIST))))
PIP?=${CWD}/bin/pip
PYTHON?=${CWD}/bin/python

BASE?=setuptools wheel


.DEFAULT: venv
venv: ${PYTHON}
${PYTHON}: requirements.txt
	python3 -mvenv ${CWD}
	${PIP} install --upgrade pip
	${PIP} install --upgrade ${BASE}
	${PIP} install -r requirements.txt

