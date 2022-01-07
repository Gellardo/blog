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

<!-- Teaser: In this post I will use python and Semgrep to validate GitLab repositories against codified guiderails. -->
<!-- Teaser: Pretrending to do Gitlab config validations to talk about Semgrep -->

Imagine this: You are migrating 50+ Repositories to a new GitLab instance.
In addition to changing CI from Jenkins to GitLab CI, you are also trying to enforce a certain set of best practices like "don't allow people to force-push the main branch".
And since those practices are new, they might change a few times before settling.
How do you ensure that after multiple months of migration, all repositories are in a similar state?

By writing automation that checks repositories against the best codified validation of the best practices possible.
I want to explain to you why and how I ended up using Semgrep for most of those validations.

If you want to see code, you can [skip all the fluff]({{< relref "#finally-checking-things" >}}).


## The Problem
There is a diverse and context-specific set of rules that need to be enforced.
At the same time, those rules are still not finished and changing, otherwise just checking them once would be sufficient.
But let's first look at the types of rules that you could encounter.

1. checking existence and content of files in the repository (ownership information, changelog files, ...)
2. CI best practices (use templates where possible, use current versions, ...)
3. GitLab repository configurations (protect important branches, require signed commits, ...)

The main sources of repository specific GitLab configuration are either in YAML configuration files or JSON API responses.
Most of the information necessary for 2 and 3 is stored in either YAML files (GitLab CI) or JSON (API responses).
Those follow some schemata that are too complex to learn just to write a few rules.
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
Hmm, so there should already be validation frameworks for json (since most of our checks are json anyways).
So how about using a specialized framework for that.

- less problems for all the exceptional dict-access cases for json
- json (perhaps yaml) only, no solution for other languages if we ever need them
- the main use cases of those is to enforce schemata for APIs, which does not quite fit what I want to do.
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
The web page is heavily about their SaaS solution, but it easily be run from python/the cli too.

How it works: Basically write patterns in yaml and let Semgrep find all the matches.
Since it works on ASTs, no need to be able to compile things (not that relevant for JSON though).

- multi-language support in case I need it
- patterns are just the same format with some intuitive additional syntax
- can add messages (with parts from the match), metadata and rule identifiers
- patterns can be tricky / need some experience about pattern interactions and how Semgrep will group elements in the AST
- some of my rules are impractical to translate <!-- (have branch protections for exactly these 4 branches) TODO link to future work -->
- very simplistic testing possibilities

So let us have a closer look instead of just singing praises at it.

## Semgrep Overview

As I already mentioned, Semgrep is all about patterns and matching them to a wide variety of languages/file types.
To do so robustly, it applies patterns on parsed abstract syntax trees instead of the original text.
If you want to play around with it, have a look at the [playground](https://semgrep.dev/editor).

The nice thing is that you don't have to know almost anything about ASTs, most of it is abstracted away from the pattern editor.
Instead, patterns mostly look like the language that is being searched with some additional options for matching bits of code.
The most important ones to understand are:
- `$NAME` which matches (and stores) a single identifier/value, called a metavariable
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
This will find any instance where a secret is retrieved and subsequently logged.

Things to keep in mind:
- This pattern matches one very specific case for the underlying problem (secrets printed to the log). There can be others that do the same thing but would not match. For example, funneling the variable through a second variable/the identity function or using an `f""` string instead of the logger string interpolation or ...
- You can add additional patterns/false-positive patterns/pattern on metavariables to increase the coverage. But you will get false positives and negatives anyways.
- Malicious minds will always be able to get around those patterns. So in the end Semgrep rules are good for providing guardrails/codifying standards in a codebase, not preventing any possible issue. For example enforcing that a logger is used everywhere instead of `print` statements..
- There are efforts for adding taint analysis and joining findings across files to Semgrep but generally patterns are restricted to a single file/function.

As you saw, the pattern was basically python code with placeholders wherever necessary.
This becomes even more apparent when matching functions.

```
def $FUNC(...):
  ...
```

You need to provide an additional placeholder for the body.
Otherwise Semgrep's parser will shout at you because it could not parse the pattern, since it was not a complete python function definition (even if the body is unspecified anyways).

Semgrep is relatively consistent between languages, but there are some subtle changes to placeholder matching behavior depending on both the current code and the language that can be hard to catch without some experience.
In JSON, `{"a":1,...}` will match both `{"b":2,"a":1}` and `{"a":1,"b":2}`, but to match both `[1,2]` and `[2,1]`  you need to use `[...,2,...]`.

Everything up until now is just a fancier way of grepping for strings.
But Semgrep allows us to combine patterns using `and`, `or` and `not` as well as specifying patterns for captured meta variables.
This allows us to further narrow down on what exactly you want to match.

You already know that your pattern will match a known good case?
Add a `pattern-not` pattern to exclude that false positive.
There is a case that does not quite fit your original pattern but has the same problem?
Wrap your original pattern in a `pattern-either` and add a specialized pattern for that case.
Want to match all functions that start with `unsafe_`?
Match all functions and capture the function name in a metavariable and add a `metavariable-regex` pattern to match the captured function name.

```yaml
- patterns:
  - pattern: print(...)
  - pattern-not-inside: |
      def log(...):
          ...
```
Pretty easy to understand, right?
Find all `print` calls, except if it is inside a `log` function because that is allowed for some reason.

## Finally checking things

Now that we are past the basics, let's look at how to accomplish the original task: validating GitLab configs.

### Default branch
Let's start with a simple one, validating the default branch.
Say our organization is using Git flow or similar.
Then all repositories should have a branch `develop` as the default branch.

First let us find an API call that contains the information that we want:
The [/projects REST call](https://docs.gitlab.com/ee/api/projects.html#get-single-project) looks promising:

```bash
$ curl -H "Content-Type: application/json" -H "PRIVATE_TOKEN:xxxxxx" gitlab.example.com/api/v4/projects/3
{
  "id": 3,
  "default_branch": "develop",
  "name": "Example Project",
  ...
}
```

As a nice side-effect, the result also has other interesting fields for further checks, e.g. `only_allow_merge_if_pipeline_succeeds`.
But the current rule is a pretty simple one, match all objects with a `default_branch` key, except if the branch name is `develop`.
We can put this (and further rules) into a file `gitlab-configs.yaml`.

```yaml
rules:
- id: default-branch-develop
  patterns:
    - pattern: |
        { "default_branch": $BRANCH, ...}
    - pattern-not: |
        { "default_branch": "develop", ...}
  message: default branch set to $BRANCH instead of develop
  languages: [json]
  severity: INFO
```

We first need to have a matching pattern, which just finds all objects with a default branch.
Once the initial scope has been set, we can use `patter-not` to exclude the known good case where the branch is develop.
We also specify a human readable message, an id for the rule and a severity to finish the configuration.

Now if we want to test those rules, let's save the results of the last curl call to `project.json`.
We can invoke Semgrep on the CLI on that file:

```
$ semgrep --config gitlab-configs.yaml project.json
```

As long as the branch name is `develop` only some status information is printed, but if the project has a different branch name, Semgrep will print a finding:
```
severity:info rule:default-branch-develop: default branch set to "master" instead of develop
1:{
2:  "id": 3,
3:  "default_branch": "master",
4:  "name": "Example Project"
5:}
```

One "problem" for larger json objects like in this case is that the smallest match seems to be a full object.
Therefore even though we are only looking at one field, the full json object / the first <n> lines are printed.
This makes visually checking the result annoying and makes useful messages a necessity.

Anyways, let's continue with a slightly more complex rule.

### Branch protections
Since we are using Git flow, there should be some basic branch protections in place everywhere.

- Noone except the CI is allowed to push to protected branches
- must protect master and develop, feature branches are OK without (ignoring release/hotfix branches)
- roles >=developer is allowed to merge

Let's start with where to get the information necessary for those rules.
Luckily there is an endpoint that does just what we want it to: `/api/v4/projects/<project_id>/protected_branches`.
See [the docs](https://docs.gitlab.com/ee/api/protected_branches.html#list-protected-branches) to view an example response.

I will dump the Semgrep rules on you and then explain what is going on in detail.

```yaml
- id: branch-protection-unknown-targets
  patterns:
    - pattern: |
        {"name":$BRANCH,...}
    - metavariable-regex:
        metavariable: $BRANCH
        regex: \"(?!(develop|master)").*
  message: found branch protection for unknown target $BRANCH
  languages: [json]
  severity: WARNING
```

This is one case where the pattern matching can get very annoying.
We are technically looking at a list of branch-protections and want to say:

> This contains exactly 1 entry for `develop` and one for `master`

After playing around with writing a pattern for a list with 2 objects with the right names, I basically gave up and put most of the logic into python.
The main problem is that the order of a list is fixed, so I would need to write a `pattern-not` for all possible permutations.

Now I hear you say: "But that is only 2 permutations, just do that"- yeah well, the actual rule had 4 branch names.
That makes 24 permutations, which is a no-go.
I also tried playing around with meta-variables, but meta-variables and `pattern-not` do not play well together.
They are only assigned in a `pattern`, which we can not use to avoid matching only faulty lists with exactly 4 elements.
Even if that worked, it is not clear to me how to formulate the "all permutations" part for the matched metavariables.

Anyways, some quick python, collecting the branch names and doing a quick `set(actual) == set(expected)` and it's done.
The rule I wrote in addition to that just showcases capturing a metavariable and then running a regex on it.
The regex basically does a negative match (using negative look-ahead) and reports all unexpected names.

```yaml
- id: branch-protection-push-access-user
  patterns:
    - pattern: |
        {"name":$BRANCH,...}
    - pattern: |
        { "push_access_levels": [
          ...,
          { "access_level_description": $GLUSER, ...  },
          ...
        ], ... }
    - metavariable-regex:
        metavariable: $GLUSER
        regex: \"(?!.*\.gitlab|No one).*\"
  message: push allowed to non-team user $GLUSER for $BRANCH
  languages: [json]
  severity: WARNING
```
This rule checks who is allowed to push to protected branches.
It is using the same logic as the previous rule but extends it to also capture the field that contains the user/group/roles required to push.
Matching strings here is not ideal, but all my CI machine users are named `<group>.gitlab` so it is sufficient for my use case.

The value also has the role name, meaning that we can match "No one" as another valid option.
Therefore, the branch protection can only allow pushes to the machine users or noone, otherwise the rule will match.

Since this is a little more complex logic going on now, it makes me want to have some assurance that the rules actually do what I expect them to do.
Thankfully, Semgrep already has some rudimentary unit-test-like functionality built in.

If our rules are in a file `rules.yaml`, we can create a `rules.json` file which contains individual test cases.
For each test case, a "comment" with either `ruleid: <rule-id>` or `ok: <rule-id>` to indicate if a match should start at that location.
Adding `ok` is useful to protect us against known good cases matching while `ruleid` marks known bad cases that should be matched.

For our branch protection, this could look like:
```json
// ruleid:branch-protection-push-access-user,branch-protection-unknown-targets
{
  "id": 128,
  "name": "some-branch",
  "push_access_levels": [
    {
      "access_level": 40,
      "access_level_description": "some.person",
      "user_id": 23,
      "group_id": null
    },
  ],
  "merge_access_levels": [
    {
      "access_level": 30,
      "access_level_description": "Developers + Maintainers",
      "user_id": null,
      "group_id": null
    }
  ],
  "allow_force_push": true,
  "unprotect_access_levels": [],
  "code_owner_approval_required": false
}
```

Since the rules above always match the whole object, the test comments have to be at the beginning of the whole object.
And both our rules will match this object because there is a non-standard team user and the protection is for branch that is not 'master' or 'develop'.

Now if we execute the tests, it looks like this:
```sh
% semgrep --test
100%|███████████████████████████████████████████████████████████████████████|2/2
1 yaml files tested
check id scoring:
--------------------------------------------------------------------------------
(TODO: 0) branch-protection-rules.yaml
	✔ branch-protection-push-access-user                   TP: 1 TN: 0 FP: 0 FN: 0
	✔ branch-protection-unknown-targets                    TP: 1 TN: 0 FP: 0 FN: 0
```

If one of the expectations fails, it produces output that only reports the expected line numbers and the actually matched lines.
```
test: <path>/branch-protection-rules.json, expected lines: [1], reported lines: [5]
```
While that is not the best reporting, it is good enough to notice regressions and then run the rules again interactively to see what went wrong.

## Conclusion and what else to do?

I liked working with Semgrep.
Starting off, it was a little annoying to find out the right combination of patterns for them to behave how I wanted.
But once I got some experience on how to write rules, it felt pretty productive.
I did open one [issue regarding test reporting](https://github.com/returntocorp/semgrep/issues/3850).

One shortcoming was having to work with json lists, because the API returned items in an inconsistent order.
I was not able to handle that in Semgrep, but luckily I could fall back to python for that and it might be a json specific problem.

The rules are relatively easy to explore and understand what is being enforced compared to arbitrary python.
At least the ones that I wrote for this project.
Having individual ids allows me to later add another layer on top.
I'm thinking about having different project types which might enforce different rules.
So Gitflow based projects might enforce a different subset of the branch protection rules that trunk-based projects.
But that's a task for another time.
