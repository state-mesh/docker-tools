REPO ?= ragflow
NAME = statemesh/$(REPO)
VERSION = 1.0.0

.PHONY: build tag tag-latest push push-latest release

release: build tag tag-latest push push-latest

build:
	docker build -t $(NAME):$(VERSION) --rm $(REPO)

tag:
	docker tag $(NAME):$(VERSION) $(NAME):$(VERSION)

tag-latest:
	docker tag $(NAME):$(VERSION) $(NAME):latest

push:
	docker push $(NAME):$(VERSION)

push-latest:
	docker push $(NAME):latest
