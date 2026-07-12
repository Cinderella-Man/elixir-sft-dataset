# Fill in the middle: `Workflow.normalize/1`

Implement the private `normalize/1` helper used by `define/2` to canonicalize a
single transition spec into the internal 4-tuple shape `{event, from, to, guard}`.
It has one argument (a transition spec) and must handle three cases via pattern
matching / multiple clauses:

1. A guardless edge `{event, from, to}` where `event`, `from`, and `to` are all
   atoms. Return `{event, from, to, nil}` (no guard, represented as `nil`).
2. A guarded edge `{event, from, to, guard}` where `event`, `from`, and `to` are
   atoms and `guard` is a **1-arity function**. Return the tuple unchanged:
   `{event, from, to, guard}`.
3. Anything else (a tuple of the wrong shape, non-atom elements, or a guard that
   is not a 1-arity function). Raise `ArgumentError` with the message
   `"invalid transition spec: #{inspect(other)}"`, where `other` is the offending
   spec.

The guards on the first two clauses are what make an invalid spec fall through to
the third clause, so ordering and guard conditions matter.

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

  @doc "Defines an FSM named by the atom from the given `states`. Returns the machine."
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
       when is_atom(event) and is_atom(from) and is_atom(to) do
    # TODO
  end

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
          {:ok, Map.put(record, :state, to)}
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