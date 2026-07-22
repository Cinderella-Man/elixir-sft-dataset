# Fill in the middle: `guard/2`

Implement the private `guard/2` function. It takes an event atom and a record
map and returns a boolean saying whether that event's transition is permitted
for the given record. Encode exactly these two guards; every other event must
always pass:

- **`:submit`** — return `true` only when the record's `:items` field is a
  non-empty list; otherwise return `false`.
- **`:approve`** — return `true` only when the record's `:approved_by` field is
  a non-empty binary (string); otherwise return `false`.
- **any other event** — always return `true`.

Prefer expressing these as multiple `defp guard/2` clauses using pattern
matching and guards (`is_list/1`, `is_binary/1`, and inequality checks), with a
catch-all clause returning `true`.

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

  @spec new(map()) :: map()
  def new(attrs \\ %{}) when is_map(attrs) do
    attrs
    |> Map.put(:state, :draft)
    |> Map.put(:history, [])
  end

  @spec states() :: [atom()]
  def states, do: @states

  @spec transition(map(), atom()) ::
          {:ok, map()}
          | {:error, :invalid_transition, atom(), atom()}
          | {:error, :guard_failed, atom(), atom()}
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
  # TODO
end
```