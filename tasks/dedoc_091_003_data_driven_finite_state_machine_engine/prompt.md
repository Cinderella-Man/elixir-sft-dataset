# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule Workflow do
  defstruct [:initial, :transitions, :states]

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

  def states(%__MODULE__{states: states}), do: states

  def new(%__MODULE__{initial: initial}, attrs \\ %{}) when is_map(attrs) do
    Map.put(attrs, :state, initial)
  end

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

  def can?(%__MODULE__{} = machine, record, event) do
    match?({:ok, _}, transition(machine, record, event))
  end
end
```
