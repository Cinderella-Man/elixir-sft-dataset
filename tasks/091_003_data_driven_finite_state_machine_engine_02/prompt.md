# Fill in the Middle: `Workflow.transition/3`

Implement the public `transition/3` function. It receives the machine struct, a
`record` map (which always has a `:state` key holding the current state atom),
and an `event` atom, and attempts to apply that event.

Find the transition in the machine whose event equals `event` and whose `from`
state equals the record's current `:state`. There is at most one such edge,
since `define/2` rejects duplicate `{event, from}` pairs.

- If a matching edge exists, inspect its guard. When the guard is `nil` (a
  guardless edge) or the guard function called on the record returns a truthy
  value, the transition succeeds: return `{:ok, updated_record}` where the
  record's `:state` is replaced by the edge's destination state and every other
  field is preserved unchanged.
- If a matching edge exists but its guard returns a falsy value, return
  `{:error, :guard_failed, current_state, event}` and leave the record
  untouched.
- If no edge matches the event from the current state (an unknown event or a
  terminal state), return `{:error, :invalid_transition, current_state, event}`.

The `:invalid_transition` check takes precedence: a guard is only ever run for an
edge that actually matches the event and current state.

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
    # TODO
  end

  @spec can?(t(), map(), atom()) :: boolean()
  def can?(%__MODULE__{} = machine, record, event) do
    match?({:ok, _}, transition(machine, record, event))
  end
end
```