---
title: "Self-Documenting Makefile"
date: 2021-06-10T16:07:25+02:00
tags: [shell]
---

A short one i really liked and I want to document for future-me:
[Self-documenting `Makefile`s](https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html).
Just add a new `help` target and now you can comment all targets by using `## <comment>` after the prerequisites.

Having to remembering which targets are available in each project (and what they do) is not ideal and I have not used them enough to standardize on a certain naming.
Enter: a short article about [self-documenting Makefiles](https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html).
<!--more--><!-- necessary because of bug(?), setting summary in frontmatter shows the whole content instead of the summary -->

{{% tip %}}

I really liked the idea and want to document it for future-me:
Makefiles can get big and cluncky quick and soon you are going to need some documentation about which target is doing what.
So either put that information into the `Readme.md` or... just add a new target that pulls the information directly from the `Makefile`.

Extracting the information from the Makefile itself has several advantages:
1. The Makefile is self-contained and does not need additional documentation.
1. Keeping the documentation close to the actual code makes it easy to (remember to) update it.

The implementation only needs an additional target, e.g. `help` that greps over the Makefile and extracts all targets which have a `## <COMMENT>` after the prerequisites.
Some `awk` shenanigans to pretty print the result and it is done.
Bonus points for setting `help` as the `.DEFAULT_GOAL` to run it if `make` is called without any arguments.

Example:
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

```shell
% make
clean                clean up leftover files
help                 Comment' indicating they can be used in a CLI
```

**TIP**:Only use `##` as the seperator between prerequisites and comment, otherwise stuff like in the example happens ;)
