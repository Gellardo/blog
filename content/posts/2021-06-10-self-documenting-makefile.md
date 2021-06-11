---
title: "Self-Documenting Makefile"
date: 2021-06-10T16:07:25+02:00
tags: [shell]
---

A short one i really liked and I want to document for future-me:
[Self-documenting `Makefile`s](https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html).
Just add a new `help` target and now you can comment all targets by using `## <comment>` after the prerequisites.

The displayed help is generated on the fly so just keep the documentation updated right next to the scripting and enjoy a nicely formatted help for all the important `make`-targets.

```make
clean: ## clean up leftover files
	@echo 'removing files'

# will not be included in the help output
internal: some-file
	@echo 'doing some internal, not to be called manually things'

.DEFAULT_GOAL := help
.PHONY: help
help: ## prints all targets followed by a '## Comment' indicating they can be used in a CLI
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
```
