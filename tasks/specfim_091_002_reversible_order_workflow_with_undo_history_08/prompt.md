# Reconstruct the missing typespec

In the otherwise-complete module below, the `@spec` for
`transition/2` has been removed; `# TODO: @spec` holds its place.
Write that one attribute — a `@spec` for `transition/2` faithful to
the arguments, guards, and every return shape the code can actually
produce. Nothing else changes.

## The module with the `@spec` for `transition/2` missing

```elixir
defmodule Workflow do
  @moduledoc """
  A finite state machine for an order lifecycle that records every applied
  transition, enabling `undo/1` and an inspectable `history/1`.

  A record is a plain map that always carries a `:state` atom and a `:history`
  list of `{event, from, to}` tuples (stored most-recent first).

  Purely functional: no processes, standard library only.
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

  @doc "Builds a new reversible order workflow from `attrs`. Returns the workflow map."
  @spec new(map()) :: map()
  def new(attrs \\ %{}) when is_map(attrs) do
    attrs
    |> Map.put(:state, :draft)
    |> Map.put(:history, [])
  end

  @spec states() :: [atom()]
  def states, do: @states

  # TODO: @spec
  def transition(%{state: current, history: history} = record, event) do
    case Map.fetch(@transitions, event) do
      {:ok, {^current, to}} ->
        if guard(event, record) do
          updated =
            record
            |> Map.put(:state, to)
            |> Map.put(:history, [{event, current, to} | history])

          {:ok, updated}
        else
          {:error, :guard_failed, current, event}
        end

      _ ->
        {:error, :invalid_transition, current, event}
    end
  end

  @spec undo(map()) :: {:ok, map()} | {:error, :nothing_to_undo}
  def undo(%{history: []}), do: {:error, :nothing_to_undo}

  def undo(%{history: [{_event, from, _to} | rest]} = record) do
    {:ok, record |> Map.put(:state, from) |> Map.put(:history, rest)}
  end

  @spec can?(map(), atom()) :: boolean()
  def can?(record, event) do
    match?({:ok, _}, transition(record, event))
  end

  @spec history(map()) :: [atom()]
  def history(%{history: history}) do
    history
    |> Enum.reverse()
    |> Enum.map(fn {event, _from, _to} -> event end)
  end

  # Guards: true when permitted.
  defp guard(:submit, %{items: items}) when is_list(items) and items != [], do: true
  defp guard(:submit, _record), do: false

  defp guard(:approve, %{approved_by: approved_by})
       when is_binary(approved_by) and approved_by != "",
       do: true

  defp guard(:approve, _record), do: false

  defp guard(_event, _record), do: true
end
```

Reply with the `@spec` attribute alone, however many lines it needs —
not the module.
