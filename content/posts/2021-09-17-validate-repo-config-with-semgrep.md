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
I want to explain to you why and how I ended up on using Semgrep for most of those validations.

If you want to see code, you can [skip all the fluff]({{< relref "#finally-checking-things" >}}).


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
Hmm, so thereshould already be validation frameworks for json (since most of our checks are json anyays).
So how avout using a specialized framework for that.

- less problems for all the exceptional dict-access cases for json
- json (perhaps yaml) only, no solution for other languages if we ever need them
- the main usecases of those is to enforce schemas for APIs, which does not quite fit what I want to do.
  Too rigid in the cases I tried.

### Validation engines
Next consideration was a n validation engine.
When working with kubernetes, you will at one point come across [OPA](https://www.openpolicyagent.org/docs/latest/kubernetes-tutorial/) (specifically Rego policies).
This is technically another json validator but with a focus on writing/enforcing validation policies.

- very general
- big investment to be able to read/write rules
- json/yaml only again

### Semgrep as a SAST with custom rules
As the title already spoiled, I will be using [Semgrep](https://semgrep.dev) to perform most of the validations.
The webpage is heavyly about their SaaS solution, but it easily be run from python/the cli too.

How it works: Basically write patterns in yaml and let semgrep find all the matches.
Since it works on ASTs, no need to be able to compile things (not that relevant for JSON though).

- multi-language support in case I need it
- patterns are just the same format with some intuitive additional syntax
- can add messages (with parts from the match), metadata and rule identifiers
- patterns can be tricky / need some experience about pattern interactions and how semgrep will group elements in the AST
- some of my rules are impractical to translate <!-- (have branch protections for exactly these 4 branches) TODO link to future work -->
- very simplistic testing possibilities

So let us have a closer look instead of just singing praises at it.

## Semgrep Overview

As I already mentioned, Semgrep is all about patterns and matching them to a wide variety of languages/filetypes.
To do so robustly, it applies patterns on parsed abstract syntax trees instead of the original text.
If you want to play around with it, have a look at the [playground](https://semgrep.dev/editor).

The nice thing is that you don't have to know almost anything about ASTs, most of it is abstracted away from the pattern editor.
Instead, patterns mostly look like the language that is beeing searched with some additional options for matching bits of code.
The most important ones to understand are:
-`$NAME` which matches (and stores) a single identifier/value, called a metavariable
- `...` which is basically saying "I don't care what is here"

<iframe title="Semgrep example no prints" src="https://semgrep.dev/embed/editor?snippet=ievans:print-to-logger" width="100%" height="432px" frameborder="0"></iframe>

```python
print(...)
```
This will find any `print` function call in your python code, no matter what parameters were supplied.

```python
$SECRET = get_secret(...)
...
logger.$FUNC(..., $SECRET, ...)
```
This will find any instance where a secet is retrieved and subsequently logged.

Things to keep in mind:
- This pattern matches one very specific case for the underlying problem (secrets printed to the log). There can be othersthat do the same thing but would not match. For example, funnelling the variable through a second variable/the identity function, using an `f""` string instead of the logger string interpolation, ...
- You can add addtional patterns/false-positive patterns/pattern on metavariables to increase the coverage. But you will get false positives and negatives anyways.
- Malicious minds will always be able to get around those patterns. So in the end semgrep rules are good for providing guardrails/codifying standards in a codebase, not preventing any possible issue. For example enforcing that a logger is used everywhere instead of `print` statements..
- There are efforts for adding taint analysis to Semgrep but generally patterns are restricted to a single file/function.

As you saw, the pattern was basically python code with placeholders wherever necessary.
This becomes even more apperent when matching functions.

```
def $FUNC(...):
  ...
```

You need to provide an additional placeholder for the body.
Otherwise Semgrep's parser will shout at you because it could not parse the pattern, since it was not a complete python function definition (even if the body is unspecified anyways).

Semgrep is relatively consistent between languages, but there are some subtle changes to placeholder matching behavior depending on both the curreent code and the language that can be hard to catch witthout some experience.
In JSON, `{"a":1,...}` will match both `{"b":2,"a":1}` and `{"a":1,"b":2}`, but to match both `[1,2]` and `[2,1]  you need to use `[...,2,...]`.

<!-- some basics about pattern, pattern-not, etc -->
<!-- no infos about how to debug patterns -->

## Finally checking things

<!-- default branch -->
<!-- branch protections -->
<!-- file content? -->

## What more to do?

<!-- different rules for different project types -->
<!-- make the rules explainable / how to document what is enforced -->
<!-- filter false positives -->
