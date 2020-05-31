---
title: "Getting Hugo to run"
date: 2020-05-31T22:48:32+02:00
tags: ["blogging", "Hugo"]
---

I wanted to have a really low friction way of practicing technical writing.
As my current employer mostly uses Blogs as PR, my first idea was to try blogging, but to start small without anyone seeing it.
<!--more--><!-- necessary because of bug(?), setting summary in frontmatter shows the whole content instead of the summary -->

## The selection process
As a techie, I did the sensible thing and just started writing my first 1-2 posts before doing anything else...
Of course not, there is so much interesting technologies out there and I have to choose the right one "for the future".
After scowering the internet for the best static site generator for blogs, I quickly decided to use [Hugo](gohugo.io) with a nice [theme](https://github.com/halogenica/beautifulhugo).
It was such a quick decision, only taking about 5-6h of googling competitors ([11ty](https://11ty.dev/), [gatsby](http://gatsbyjs.org/)) and deciding between some top 20 Hugo themes.

Setup of Hugo is pretty simple, a quick `brew install hugo` and adding the theme as a submodule in the `themes` directory and I had a local setup running.
Now to make it (potentially) visible for other people, I also set up GitHub Pages.
I chose the slightly more complicated way of using a seperate branch for the generated site, strictly splitting source files and generated files into different branches.

## How not to change branches all the time

Git has a neat feature called worktrees.
It allows to checkout different branches into different folders in the filesystem.
This makes it possible to e.g. review a PR of a seperate branch without having to stash/WIP-commit/... your current work.
Or let Hugo generate the site directly to the right branch ([docs](https://gohugo.io/hosting-and-deployment/hosting-on-github/#deployment-of-project-pages-from-your-gh-pages-branch).

After setting up an completely empty branch (using `checkout --orphan` and `commit --allow-empty`), we can checkout the branch in the `./public` directory:
```bash
git worktree add -B gh-pages public origin/gh-pages
```

Now deployments are really simple:
```bash
# generates the site in ./public
hugo
# change into dir for doing git commands
cd public && git add --all && git commit -m "update blog" && cd ..
```

Later on, I want to automate this using GitHub Actions to automatically update the site on pushes to `master`.
But that's my time for today.
