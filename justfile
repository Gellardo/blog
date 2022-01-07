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

# checks a running local hugo site for broken links, takes a while
broken-links:
  wget --spider -r -nd -nv -H -l 1 -w 2 -o run1.log  http://localhost:1313/blog/
  grep -B1 "broken link"

# idempotent setup logic
@setup:
  @# not doing package management, assumes that hugo is installed
  if git worktree list | grep -q '/public .* \[gh-pages]'; then \
    echo "worktree already set up"; \
  else \
    git worktree add -B gh-pages public origin/gh-pages; \
  fi
