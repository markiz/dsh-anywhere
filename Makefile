# The launcher expects this exact tag.
PREFIX ?= $(HOME)/.local

.PHONY: image test lint run install uninstall

image:
	docker build -t dsh-anywhere:latest .

run:
	./dsh-anywhere

test:
	bash -n dsh-anywhere
	bash -n entrypoint.sh
	bash tests/smoke.sh

lint:
	shellcheck dsh-anywhere entrypoint.sh tests/smoke.sh

install:
	install -d "$(PREFIX)/bin"
	ln -sf "$(CURDIR)/dsh-anywhere" "$(PREFIX)/bin/dsh-anywhere"

uninstall:
	rm -f "$(PREFIX)/bin/dsh-anywhere"
