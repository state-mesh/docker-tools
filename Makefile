REPO ?= ragflow
NAME = registry.densemax.local/statemesh/$(REPO)
VERSION = 1.0.0

.PHONY: build tag tag-latest push push-latest release

release: build tag tag-latest push push-latest

build:
	buildah build --layers=true --format=docker -t $(NAME):$(VERSION) $(REPO)

tag:
	buildah tag $(NAME):$(VERSION) $(NAME):$(VERSION)

tag-latest:
	buildah tag $(NAME):$(VERSION) $(NAME):latest

push:
	buildah push --tls-verify=false push $(NAME):$(VERSION)

push-latest:
	buildah push --tls-verify=false push $(NAME):latest
