# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

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

## The buggy module

```elixir
defmodule Workflow do
  @moduledoc """
  A generic, data-driven finite state machine engine.

  A machine is defined via `define/2` from an initial state and a list of
  transition specs (`{event, from, to}` or `{event, from, to, guard}`). The same
  engine then drives any machine so defined.

  Purely functional: no processes, standard library only.
  """

  defstruct [:initial, :transitions, :states]

  @type t :: %__MODULE__{
          initial: atom(),
          transitions: [{atom(), atom(), atom(), (map() -> boolean()) | nil}],
          states: [atom()]
        }

  @doc """
  Builds an FSM from its `initial` state atom and a list of transition
  specs. Returns the machine; raises `ArgumentError` on a malformed or
  duplicate transition spec.
  """
  @spec define(atom(), list()) :: t()
  def define(initial, transitions) when is_atom(initial) and is_list(transitions) do
    normalized = Enum.map(transitions, &normalize/1)

    keys = Enum.map(normalized, fn {event, from, _to, _guard} -> {event, from} end)

    if length(keys) != length(Enum.uniq(keys)) do
      raise ArgumentError, "duplicate transition for the same {event, from} pair"
    end

    states =
      normalized
      |> Enum.flat_map(fn {_e, from, to, _g} -> [from, to] end)
      |> then(&[initial | &1])
      |> Enum.uniq()

    %__MODULE__{initial: initial, transitions: normalized, states: states}
  end

  defp normalize({event, from, to})
       when is_atom(event) and is_atom(from) and is_atom(to),
       do: {event, from, to, nil}

  defp normalize({event, from, to, guard})
       when is_atom(event) and is_atom(from) and is_atom(to) and is_function(guard, 1),
       do: {event, from, to, guard}

  defp normalize(other),
    do: raise(ArgumentError, "invalid transition spec: #{inspect(other)}")

  @spec states(t()) :: [atom()]
  def states(%__MODULE__{states: states}), do: states

  @spec new(t(), map()) :: map()
  def new(%__MODULE__{initial: initial}, attrs \\ %{}) when is_map(attrs) do
    Map.put(attrs, :state, initial)
  end

  @spec transition(t(), map(), atom()) ::
          {:ok, map()}
          | {:error, :invalid_transition, atom(), atom()}
          | {:error, :guard_failed, atom(), atom()}
  def transition(%__MODULE__{transitions: transitions}, %{state: current} = record, event) do
    case Enum.find(transitions, fn {e, from, _to, _g} -> e == event and from == current end) do
      {_event, ^current, to, guard} ->
        if guard == nil or guard.(record) do
          {:error, Map.put(record, :state, to)}
        else
          {:error, :guard_failed, current, event}
        end

      nil ->
        {:error, :invalid_transition, current, event}
    end
  end

  @spec can?(t(), map(), atom()) :: boolean()
  def can?(%__MODULE__{} = machine, record, event) do
    match?({:ok, _}, transition(machine, record, event))
  end
end
```

## Failing test report

```
8 of 23 test(s) failed:

  * test walks the full order happy path
      
      
      match (=) failed
      code:  assert {:ok, rec} = Workflow.transition(m, rec, :submit)
      left:  {:ok, rec}
      right: {:error, %{state: :submitted, items: [:widget], approved_by: "mgr"}}
      

  * test door machine transitions independently
      
      
      match (=) failed
      code:  assert {:ok, rec} = Workflow.transition(m, rec, :lock)
      left:  {:ok, rec}
      right: {:error, %{state: :locked}}
      

  * test transition preserves unrelated fields
      no match of right hand side value:
      
          {:error, %{meta: %{c: 1}, state: :submitted, items: [:a]}}
      

  * test approve guard is enforced from the data-defined edge
      no match of right hand side value:
      
          {:error, %{state: :submitted, items: [:a], approved_by: "boss"}}
      

  (…4 more)
```
