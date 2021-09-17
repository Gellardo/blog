---
title: "Validate GitLab Repository Configuration With Semgrep"
date: 2021-09-17T22:37:06+02:00
tags: ["Semgrep"]
draft: true
---

<!--
basic structure:
1. Quick overview what are we doing why
2. The problem
3. Why use Semgrep as the solution
4. Example code (python + rules)
5. What else could I do?
-->

<!-- Teaser: In this post I will use python and semgrep to validate GitLab repositories against codified guiderails. -->

Imagine this: You are migrating 50+ Repositories to a new GitLab instance.
In addition to changing CI from Jenkins to GitLab CI, you are also trying to enforce a certain set of best practices like "don't allow people to force-push the main branch".
And since those practices are new, they might change a few times before settling.
How do you ensure that after multiple months of migration, all repositories are in a similar state?

By writing automation that checks repositories against the best codified validation of the best practices possible.
I want to explain to you why and how I ended up on useing Semgrep for most of those validations.


## The Problem
There is a diverse and context-specific set of rules that need to be enforced.
At the same time, those rules are still not finished and changing, otherwise just checking them once would be sufficient.
But let's first look at the types of rules that you could encounter.

1. checking existence and content of files in the repository (ownership information, changelog files, ...)
2. CI best practices (use templates where possible, use current versions, ...)
3. GitLab repository configurations (protect imporant branches, require signed commits, ...)

The main sources of repository specific GitLab configuration are either in YAML configuration files or JSON API responses.
Most of the information necessary for 2 and 3 is stored in either YAML files (GitLab CI) or JSON (API responses).
Those follow some schemas that are too complex to learn just to write a few rules.
So we will write some ad-hoc checks that have to know just enough to validate that one assertion it has to check.

<!-- perhaps: why are we doing it automatically? example changes, human error, overview, single source of truth -->

<!-- multiple options: write parsing code, json validation library, semgrep (pattern matching) -->
<!-- Basically I want to be able to look for a pattern, find it and enforce it ==>
