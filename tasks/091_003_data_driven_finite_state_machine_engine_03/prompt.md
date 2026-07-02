# Implement `define/2`

Implement the public `define/2` function, the constructor for the state machine
engine. It takes an initial state atom and a list of transition specs, and returns a
`%Workflow{}` struct.

`define/2` should:

1. Guard its clause on `is_atom(initial)` and `is_list(transitions)`.
2. Normalize every transition spec by mapping each one through the private
   `normalize/1` helper. `normalize/1` turns `{event, from, to}` into
   `{event, from, to, nil}`, keeps a valid `{event, from, to, guard}` (where `guard`
   is a 1-arity function) as-is, and raises `ArgumentError` for anything else — so you
   do not need to validate spec shapes yourself, just delegate to it.
3. Detect non-determinism: collect the `{event, from}` pair of each normalized
   transition and, if any pair is duplicated, raise `ArgumentError` (compare the count
   of the keys against the count of their `Enum.uniq/1`).
4. Compute the list of distinct states: flat-map each normalized transition to its
   `from` and `to`, prepend the `initial` state, and deduplicate with `Enum.uniq/1`.
5. Return `%Workflow{initial: initial, transitions: normalized, states: states}`.

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

  @spec define(atom(), list()) :: t()
  def define(initial, transitions) when is_atom(initial) and is_list(transitions) do
    # TODO
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