# Fill in one @spec

Below: a working module where the `@spec` for
`can?/3` has been removed (see the `# TODO: @spec` marker).
Provide exactly that typespec, consistent with the implementation's
arguments, guards, and all reachable return shapes. No other edits.

## The module with the `@spec` for `can?/3` missing

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
          {:ok, Map.put(record, :state, to)}
        else
          {:error, :guard_failed, current, event}
        end

      nil ->
        {:error, :invalid_transition, current, event}
    end
  end

  # TODO: @spec
  def can?(%__MODULE__{} = machine, record, event) do
    match?({:ok, _}, transition(machine, record, event))
  end
end
```

The `@spec` attribute only — nothing more.
