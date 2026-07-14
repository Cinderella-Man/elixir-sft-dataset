# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule Workflow do
  @moduledoc """
  A finite state machine for the lifecycle of an order.

  An order record is a plain map that always carries a `:state` key holding the
  current state atom. It moves through the following states:

      draft → submitted → approved → in_progress → completed

  with two side branches:

      submitted → rejected
      in_progress → cancelled

  The states `:completed`, `:rejected`, and `:cancelled` are terminal — no event
  can move an order out of them.

  This module is purely functional: it neither spawns nor relies on any
  processes, and it uses only the Elixir/OTP standard library.
  """

  @states [
    :draft,
    :submitted,
    :approved,
    :in_progress,
    :completed,
    :rejected,
    :cancelled
  ]

  # event => {from, to}
  @transitions %{
    submit: {:draft, :submitted},
    approve: {:submitted, :approved},
    reject: {:submitted, :rejected},
    start: {:approved, :in_progress},
    complete: {:in_progress, :completed},
    cancel: {:in_progress, :cancelled}
  }

  @doc """
  Build a new record.

  Returns `attrs` merged with `%{state: :draft}`. Any `:state` provided in
  `attrs` is overridden — a new record always starts in `:draft`.
  """
  @spec new(map()) :: map()
  def new(attrs \\ %{}) when is_map(attrs) do
    Map.put(attrs, :state, :draft)
  end

  @doc """
  Return the list of all seven state atoms.
  """
  @spec states() :: [atom()]
  def states, do: @states

  @doc """
  Attempt to apply `event` to `record`.

    * On success, returns `{:ok, updated_record}` with the `:state` field
      replaced by the destination state and all other fields preserved.
    * If `event` is not a valid transition out of the current state (including
      any event fired from a terminal state, or an unknown event), returns
      `{:error, :invalid_transition, current_state, event}`.
    * If the event is a valid edge but its guard rejects the record, returns
      `{:error, :guard_failed, current_state, event}`.
  """
  @spec transition(map(), atom()) ::
          {:ok, map()}
          | {:error, :invalid_transition, atom(), atom()}
          | {:error, :guard_failed, atom(), atom()}
  def transition(%{state: current} = record, event) do
    case Map.fetch(@transitions, event) do
      {:ok, {^current, to}} ->
        if guard(event, record) do
          {:ok, Map.put(record, :state, to)}
        else
          {:error, :guard_failed, current, event}
        end

      _ ->
        {:error, :invalid_transition, current, event}
    end
  end

  @doc """
  Return `true` if `transition(record, event)` would succeed, otherwise `false`.
  """
  @spec can?(map(), atom()) :: boolean()
  def can?(record, event) do
    match?({:ok, _}, transition(record, event))
  end

  # Guards: return true when the transition is permitted.

  defp guard(:submit, %{items: items}) when is_list(items) and items != [], do: true
  defp guard(:submit, _record), do: false

  defp guard(:approve, %{approved_by: approved_by})
       when is_binary(approved_by) and approved_by != "",
       do: true

  defp guard(:approve, _record), do: false

  # All other transitions have no guard and always pass.
  defp guard(_event, _record), do: true
end
```

## New specification

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
