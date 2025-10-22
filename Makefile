REPO ?= ragflow
NAME = registry.densemax.local/statemesh/$(REPO)
VERSION = 1.0.0

.PHONY: build tag tag-latest push push-latest release

ensure-buildah:
	@command -v buildah >/dev/null 2>&1 || { \
		echo "⚙️  buildah not found. Installing..."; \
		if command -v apt-get >/dev/null 2>&1; then \
			sudo apt-get update && sudo apt-get install -y buildah; \
		else \
			echo "❌ No supported package manager found. Please install buildah manually."; \
			exit 1; \
		fi \
	}

release: ensure-buildah build tag tag-latest push push-latest

build: ensure-buildah
	buildah build --layers --format=docker -t $(NAME):$(VERSION) $(REPO)

tag:
	buildah tag $(NAME):$(VERSION) $(NAME):$(VERSION)

tag-latest:
	buildah tag $(NAME):$(VERSION) $(NAME):latest

push:
	buildah push --tls-verify=false $(NAME):$(VERSION)

push-latest:
	buildah push --tls-verify=false $(NAME):latest
