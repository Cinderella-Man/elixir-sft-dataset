# Change Request — TICKET-SLA-1: Deadline-Escalating Ticket Workflow Server

**To:** Platform / Workflow team
**From:** Support Tooling maintainer
**Subject:** Replace the pure `Workflow` state machine with a *live, per-ticket
process* that enforces SLA deadlines by auto-escalating stalled tickets.

We are moving ticket lifecycle enforcement out of the request path and into a
long-lived process, one per ticket, so that a ticket that sits too long in a
state escalates on its own — without anyone having to poll it. Please implement
the module described below.

## 1. Module and shape

Implement a module named `WorkflowServer` that **is a `GenServer`**. Each server
process owns the lifecycle of exactly one ticket. All public functions take an
explicit server reference (the pid returned by `start_link/1`) as their first
argument.

## 2. States and manual transition table

A ticket moves through these states:

```
triage → assigned → working → resolved → closed
```

with a re-entry edge out of the escalation state:

```
escalated → assigned
```

The full set of states is `:triage`, `:assigned`, `:working`, `:resolved`,
`:closed`, `:escalated`.

Manual events (fired by callers via `fire/2`) map to exactly one `from → to`
edge each:

| event      | from         | to          |
|------------|--------------|-------------|
| `:assign`  | `:triage`    | `:assigned` |
| `:assign`  | `:escalated` | `:assigned` |
| `:begin`   | `:assigned`  | `:working`  |
| `:resolve` | `:working`   | `:resolved` |
| `:close`   | `:resolved`  | `:closed`   |

`:closed` is **terminal** — no event (manual or automatic) moves a ticket out of
it. `:escalated` is **not** terminal: only `:assign` leaves it, and — importantly
— `:escalated` is reachable **only** through an automatic timeout (see §5), never
through a manual event.

## 3. Starting a server

`WorkflowServer.start_link(opts)` starts a server and returns `{:ok, pid}`.
`opts` is a keyword list:

- `:deadlines` — a map of `state => milliseconds`. Default `%{}` (no deadlines,
  i.e. no automatic escalation ever).
- `:notify` — a 1-arity function invoked on every transition (see §6). Default:
  none.

A newly started ticket always begins in state `:triage`.

## 4. Querying and firing

- `WorkflowServer.current(server)` — return the current state atom.

- `WorkflowServer.allowed(server)` — return the **sorted** list of *manual*
  events that would succeed from the current state right now. It never contains
  `:timeout`. From `:closed` it is `[]`; from `:escalated` it is `[:assign]`.

- `WorkflowServer.fire(server, event)` — attempt to apply a manual `event`:
  - On success, return `{:ok, new_state}`.
  - If `event` is not a valid manual edge out of the current state (including any
    event from `:closed`, an unknown event, or the reserved `:timeout` event,
    which is **not** manually fireable), return
    `{:error, :invalid_transition, current_state, event}` and leave the ticket
    unchanged.

- `WorkflowServer.stop(server)` — stop the server; returns `:ok`.

## 5. Deadlines and automatic escalation (the time model)

When a server **enters** a state `S`, it consults `:deadlines`:

- If `S` has an entry in `:deadlines` **and** `S` is neither `:escalated` nor the
  terminal `:closed`, the server schedules a single deadline timer of
  `deadlines[S]` milliseconds. Entering the initial `:triage` state schedules
  such a timer too, if `:triage` is present in the map.
- If `S` is `:escalated` or `:closed`, **no deadline is ever scheduled**, even if
  the map contains an entry for it.

If the deadline elapses while the ticket is *still in `S`*, the server performs
an **automatic** transition `S → :escalated`, recorded with the reserved event
atom `:timeout`.

### 5.1 Cancel-on-leave (required)

If any transition moves the ticket out of `S` **before** that state's deadline
elapses, the deadline scheduled on entering `S` is cancelled and **must never
fire**. In particular, a stale timer left over from a state the ticket has
already left must not cause a later escalation: once you leave a state, that
state's scheduled deadline is dead.

### 5.2 Fresh scheduling on re-entry (required)

Every time the ticket enters a state, deadline evaluation starts over from
scratch for that state per the rules in §5. For example, escalating out of
`:triage`, then `:assign`-ing back to `:assigned`, arms a **new** deadline for
`:assigned` (if one is configured) — timed from the moment `:assigned` was
entered, independent of any earlier state's timing.

## 6. The notify callback

If `:notify` is supplied, it is called **once per transition** — for both manual
transitions and automatic timeout escalations — with a single 3-tuple argument
`{from_state, to_state, event}`, where `event` is the manual event atom, or
`:timeout` for an automatic escalation.

If the callback raises (or otherwise throws/exits), the failure is **isolated**:
it is caught and swallowed, the transition still takes effect, and the server
keeps running and remains responsive to further calls. A misbehaving callback
must never crash the workflow server.

## 7. Constraints

- Single file, module named `WorkflowServer`, implemented as a `GenServer`.
- Use only the Elixir/OTP standard library — no external dependencies.