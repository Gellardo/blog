---
title: "Exploring Semgrep for Bash linting"
date: 2021-09-03T09:29:30+02:00
tags: ["Semgrep"]
draft: true
---

Found some failure in bash scripts: using unexported functions in subshells.
Thought: That's something where having a grep rule would be nice and kind of "the usecase for semgrep" - guardrails.
But Bash is not supported -> Experimental Generic parser.

Writing the "straight forward rule"
Hitting my head at at least 2 bugs: non-matching of functions and not finding the associated export -f (Metavariable not the same?)
Trying to debug by making smaller/individual steps do what they are supposed to and then composition.

Debugging?
Bugreport?
some code at +1-projects/semgrep-rules

## Initial try

```yaml
rules:
  - id: missing-export
    languages:
      - generic
    paths:
      include:
        - "*.sh"
    severity: WARNING
    message: "Bash: function $X uses $Y and is exported but $Y is not."
    patterns:
      - pattern: |
          function $Y {
            ...
          }
          ...
          function $X {
            ...
            $Y
            ...
          }
          ...
          export -f $X
      - pattern-not: |
          ...
          export -f $Y
          ...
```

Now this should match on `a` but not `b` (TODO why?):

```bash
# ruleid:missing-export
function a {
  echo hello
}
# todook:missing-export
function b {
  a
  echo world!
}
export -f b
function c {
  b
  echo world!
}
export -f c
```

## Well go to basics and build up
ok, simplify, find the functions
```yaml
rules:
  - id: function
    languages:
      - generic
    severity: INFO
    message: "Bash: found function $X."
    patterns:
      - pattern: |
          function $X {
            ...
          }
```
finds everything

```yaml
  - id: exported-function
    languages:
      - generic
    severity: INFO
    message: "Bash: found exported function $Y."
    patterns:
      - pattern: |
          function $Y {
          ...
          }
      - pattern: export -f $Y
```
Does not match anything... Because the first pattern constricts the places where the second pattern can be found.
```yaml
  - id: exported-function
    languages:
      - generic
    severity: INFO
    message: "Bash: found exported function $Y."
    patterns:
      - pattern: |
          function $Y {
          ...
          }
          ...
      - pattern: export -f $Y
```
Matches only c?
Let's switch them around, adding `...` to match more lines
```yaml
  - id: exported-function
    languages:
      - generic
    severity: INFO
    message: "Bash: found exported function $Y."
    patterns:
      - pattern: |
          ...
          export -f $Y
          ...
      - pattern: |
          function $Y {
          ...
          }
```
matches only b?

now let's look for non-exported functions
```yaml
  - id: unexported-function
    languages:
      - generic
    severity: INFO
    message: "Bash: found unexported function $Y."
    patterns:
      - pattern: |
          function $Y {
          ...
          }
          ...
      - pattern-not: export -f $Y
```
finds a and c? even though the same with `pattern` instead of `pattern-not` matched only c.

## Is this only because generic is weird?
Ok, let's try the same in python
```yaml
rules:
  - id: exported-function
    languages:
      - python
    severity: WARNING
    message: "Python: exported $Y."
    patterns:
      - pattern: |
          def $Y():
            ...
          ...
      - pattern: export($Y)
```
```python
# ruleid:missing-export
def a():
  print "hello"
# todook:missing-export
def b():
  a()
  print "world!"
export(b)
def c():
  b()
  print "world!"
export(c)
```
 that matches b and c

Introducing `-not`
```yaml
rules:
  - id: unexported-function
    languages:
      - python
    severity: WARNING
    message: "Python: unexported $Y."
    patterns:
      - pattern: |
          def $Y():
            ...
          ...
      - pattern-not: export($Y)
```
makes it weird: multiple matches for every `def` line

So that might be because there might be line combinations in the first pattern match that don't match the second one?
Now try the more expressive variation
```yaml
rules:
  - id: unexported-function
    languages:
      - python
    severity: WARNING
    message: "Python: unexported $Y."
    patterns:
      - pattern: |
          def $Y():
            ...
          ...
      - pattern-not: |
          def $Y():
            ...
          ...
          export($Y)
```
Same problem 5xa, 3xb, 1xc, pattern-not does not like open-ended patterns i guess

```yaml
rules:
  - id: unexported-function
    languages:
      - python
    severity: WARNING
    message: "Python: unexported $Y."
    patterns:
      - pattern: |
          def $Y():
            ...
          ...
          def $X():
            ...
            $Y()
            ...
          ...
          export($X)
      - pattern-not: |
          export($Y)
```
same problem..., matches on a and b instead of just on a

## TODO
try to use `pattern-not-inside` as in open-never-close [here](https://www.i-programmer.info/news/90-tools/13725-semgrep-more-than-just-a-glorified-grep.html)
