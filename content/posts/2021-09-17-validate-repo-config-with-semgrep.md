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

## The possible Solutions

So I want to have a simple way to look for a pattern in different languages (JSON, Python, ...).
If that pattern is found, I want to generate a finding with some kind of message.
Optionally having some information about "why is that a problem" would be nice too.

I am not looking for any kind of automatic enforcing or fixing for those findings.
The results will be consumed by a human that knows what to do.

### DIY: How hard can it be to validate files

Well, since we are writing checks in python anyways, why not just write code to do it?
No domain-specific language to learn, just normal code.

- very general, can do anything
- need to do anything
  - setup test framework
  - need to remember to check all exceptional cases (json = dict = a lot of dict accesses that all can fail)
  - can get very complex for more advanced patterns
### General validation frameworks: Just build custom rules on that
Hmm, so should already be validation frameworks for json (since most of our checks are json anyays) so perhaps check for a specialized framework for that.

- less problems for all the exceptional cases for json
- json (perhaps yaml) only, no solution for other languages if we want them
- the main usecases of those is to enforce schemas for APIs, which does not quite fit what I want to do
### Validation engines
[OPA](https://www.openpolicyagent.org/docs/latest/kubernetes-tutorial/) (specifically Rego policies), json only.

- very general
- big investment to be able to read/write rules
### Semgrep as a SAST with custom rules
[Semgrep](https://semgrep.dev) (can also be run without the SaaS stuff).

- multi-language support in case I need it
- patterns are just the same format with some easy to understand additional syntax
- can add messages (with parts from the match), metadata and rule identifiers
- patterns can be tricky / need some experience
- some of my rules are impractical to translate(have branch protections for exactly these 4 branches)
- very simplistic testing possibilities

So: on to use semgrep as my finding generator (except for certain checks that are hard to do with it)
<!-- multiple options: write parsing code in python, json validation library, semgrep (pattern matching), OPA -->

## Semgrep Overview

<!-- easy to write patterns, relatively consistent across languages -->
<!-- patterns look easy but you need some time to get a feel for the grouping behavior -->
<!-- no infos about how to debug patterns -->

## Let's check things

<!-- default branch -->
<!-- branch protections -->
<!-- file content? -->

## What more to do?

<!-- different rules for different project types -->
<!-- make the rules explainable / how to document what is enforced -->
<!-- filter false positives -->
