# run development server
run-dev:
  hugo server -D

# publish the current state to github pages
publish:  setup
  #!/usr/bin/env bash
  set -euxo pipefail

  hugo
  ORIGIN_COMMIT="$(git log --format="%h: %B" -n 1 |head -n1)$(git diff --quiet || echo ' - dirty')"

  # assumes that public is a worktree checked out to the gh-pages branch
  cd public
  git commit -am "Update Blog \"$ORIGIN_COMMIT\""
  git push

# idempotent setup logic
@setup:
  @# not doing package management, assumes that hugo is installed
  if git worktree list | grep -q '/public .* \[gh-pages]'; then \
    echo "worktree already set up"; \
  else \
    git worktree add -B gh-pages public origin/gh-pages; \
  fi
