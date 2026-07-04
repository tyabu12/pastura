# Mirror detector fixture

## FIRE: near-complete drifted copy of data/alpha.yaml

```yaml
id: alpha
name: Alpha scenario CHANGED
agents: 3
rounds: 2
personas:
  - name: One
    role: chief
  - name: Two
    role: follower
phase: speak_all
```

## SILENT: identical copy of data/beta.yaml (in sync, not a current drift)

```yaml
id: beta
name: Beta scenario
agents: 4
rounds: 1
personas:
  - name: Alice
    role: host
  - name: Bob
    role: guest
phase: vote
```

## SILENT: abridged excerpt of data/gamma.yaml (below completeness threshold)

```yaml
id: gamma
name: Gamma scenario
agents: 5
rounds: 3
personas:
  - name: P1
    role: r1
  - name: P2
    role: r2
```

## SILENT: coincidental id match, unrelated content (below ratio floor)

```yaml
id: alpha
title: completely unrelated content here
foo: bar
baz: qux
items:
  - one
  - two
  - three
  - four
tail: done
```

## SILENT: no id on the first line (unattributable)

```yaml
name: block with no id first line
agents: 3
rounds: 2
personas:
  - name: One
    role: leader
  - name: Two
    role: follower
phase: speak_all
```

## SILENT: id resolves to no source file

```yaml
id: zeta
name: Zeta scenario
agents: 3
rounds: 2
personas:
  - name: One
    role: leader
  - name: Two
    role: follower
phase: speak_all
```

## FIRE: indented fenced block under a list item (dedent to fence indent)

1. A scenario embedded in a list item:

   ```yaml
   id: delta
   name: Delta scenario CHANGED
   agents: 2
   rounds: 5
   personas:
     - name: X
       role: a
     - name: Y
       role: b
   phase: choose
   ```

## FIRE: tilde fence whose content contains a backtick fence (no early close)

~~~yaml
id: epsilon
name: Epsilon CHANGED
note: |
  ```
  code sample inside
  ```
agents: 1
rounds: 1
phase: assign
~~~
