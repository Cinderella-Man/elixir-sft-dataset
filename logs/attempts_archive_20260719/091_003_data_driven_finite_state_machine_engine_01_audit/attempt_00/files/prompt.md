# Data-Driven Finite State Machine Engine

Write me an Elixir module called `Workflow` that is a **generic, reusable finite
state machine engine**. Instead of hard-coding one order lifecycle, the machine
definition (its states, transitions, and guards) is supplied as **data**, and
the same engine drives any machine built that way.

## Building a machine

- `Workflow.define(initial, transitions)` — build and return a machine value.
  - `initial` is the atom the machine starts in.
  - `transitions` is a list of transition specs. Each spec is either:
    - `{event, from, to}` — a guardless edge, or
    - `{event, from, to, guard}` — where `guard` is a **1-arity function**
      `fn record -> boolean end` that decides whether the transition is
      permitted for a given record.
  - `event`, `from`, and `to` are atoms.

  `define/2` must reject malformed input by raising `ArgumentError`:
  - a transition spec that isn't one of the two shapes above (including a guard
    that is not a 1-arity function), and
  - two transitions that share the same `{event, from}` pair (which would make
    the machine non-deterministic).

- `Workflow.states(machine)` — return the list of all distinct states reachable
  in the machine: the `initial` state plus every `from`/`to` appearing in the
  transitions, deduplicated. (Order is unspecified.)

A state with **no outgoing transitions** is effectively terminal: no event
applies from it.

## Records

A *record* is a plain map that always contains a `:state` key holding the
current state atom, plus any additional domain fields (preserved untouched
across transitions).

- `Workflow.new(machine, attrs \\ %{})` — build a new record for `machine`.
  Returns `attrs` merged with `%{state: machine_initial}` (the `:state` in
  `attrs`, if any, is overridden). `attrs` is a map with atom keys.

## Running the machine

- `Workflow.transition(machine, record, event)` — attempt to apply `event`.
  - On success, return `{:ok, updated_record}` where `:state` is replaced by the
    edge's destination and all other fields are preserved.
  - If no edge matches `event` from the record's current state (including a
    terminal state or an unknown event), return
    `{:error, :invalid_transition, current_state, event}`.
  - If a matching edge exists but its guard returns a falsy value, return
    `{:error, :guard_failed, current_state, event}` and leave the record
    unchanged. The `:invalid_transition` check takes precedence: only a matching
    edge ever runs a guard.

- `Workflow.can?(machine, record, event)` — return `true` if
  `Workflow.transition(machine, record, event)` would succeed (matching edge
  **and** guard passes), otherwise `false`.

## Constraints

- Single file, module named `Workflow`.
- Use only the Elixir/OTP standard library — no external dependencies.
- No processes are required; this is a pure functional module.