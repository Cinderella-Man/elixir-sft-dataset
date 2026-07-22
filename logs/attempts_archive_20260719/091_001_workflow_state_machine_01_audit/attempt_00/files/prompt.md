# Workflow State Machine

Write me an Elixir module called `Workflow` that defines and enforces a finite
state machine for the lifecycle of an order.

## States

The order moves through these states:

```
draft → submitted → approved → in_progress → completed
```

with two side branches:

```
submitted → rejected
in_progress → cancelled
```

So the complete set of states is:

`:draft`, `:submitted`, `:approved`, `:in_progress`, `:completed`,
`:rejected`, `:cancelled`.

The states `:completed`, `:rejected`, and `:cancelled` are **terminal** — no
event can move an order out of them.

## Transition table

Each event is an atom and maps to exactly one `from → to` edge:

| event       | from          | to            |
|-------------|---------------|---------------|
| `:submit`   | `:draft`      | `:submitted`  |
| `:approve`  | `:submitted`  | `:approved`   |
| `:reject`   | `:submitted`  | `:rejected`   |
| `:start`    | `:approved`   | `:in_progress`|
| `:complete` | `:in_progress`| `:completed`  |
| `:cancel`   | `:in_progress`| `:cancelled`  |

## The record

A *record* is a plain map that always contains a `:state` key holding the
current state atom, plus any additional domain fields. Other fields must be
preserved untouched across a transition.

## Public API

- `Workflow.new(attrs \\ %{})` — build a new record. It returns a map that is
  `attrs` merged with `%{state: :draft}` (the `:state` in `attrs`, if any, is
  overridden — a new record always starts in `:draft`). `attrs` is a map with
  atom keys.

- `Workflow.states/0` — return the list of all seven state atoms.

- `Workflow.transition(record, event)` — attempt to apply `event` to `record`.
  - On success, return `{:ok, updated_record}` where `updated_record` is
    `record` with its `:state` replaced by the destination state and all other
    fields preserved.
  - If `event` is not a valid transition out of the record's current state
    (including any event fired from a terminal state, or an unknown event),
    return `{:error, :invalid_transition, current_state, event}`.
  - If the event *is* a valid edge but its guard function rejects the record
    (see below), return `{:error, :guard_failed, current_state, event}`.
  - The `:invalid_transition` check takes precedence over the guard check: only
    valid edges ever run a guard.

- `Workflow.can?(record, event)` — return `true` if calling
  `Workflow.transition(record, event)` would succeed (valid edge **and** its
  guard passes), otherwise `false`.

## Guards

A transition may have a guard function that inspects the record and decides
whether the transition is permitted. Encode exactly these two guards; all other
transitions have no guard and always pass:

- **`:submit`** (`:draft → :submitted`): passes only when the record's `:items`
  field is a non-empty list. A missing `:items` key, a non-list value, or an
  empty list `[]` all cause the guard to fail.

- **`:approve`** (`:submitted → :approved`): passes only when the record's
  `:approved_by` field is a non-empty binary (string). A missing key, `nil`, a
  non-binary value, or the empty string `""` all cause the guard to fail.

When a guard fails, `transition/2` returns
`{:error, :guard_failed, current_state, event}` and the record is left
unchanged.

## Constraints

- Single file, module named `Workflow`.
- Use only the Elixir/OTP standard library — no external dependencies.
- No processes are required; this is a pure functional module.