# Implement `transition/2`

Implement the public `transition/2` function. It takes a record (a map that
carries a `:state` atom and a `:history` list) and an `event` atom, and attempts
a **forward** transition according to the module's `@transitions` table.

Look up `event` in `@transitions` to find its `{from, to}` edge. The event is a
valid forward transition only when it exists in the table **and** its `from`
state matches the record's current `:state`. When that is the case, run the
transition's guard for the event against the record using the private `guard/2`
helper:

- If the guard passes, produce the updated record: replace `:state` with the
  destination state `to`, and prepend a `{event, current, to}` history entry to
  the front of the existing `:history` list (history is stored most-recent
  first). Return `{:ok, updated_record}`. All other domain fields must be left
  untouched.
- If the guard fails, leave the record unchanged and return
  `{:error, :guard_failed, current_state, event}`.

If `event` is not in the table, or its `from` does not match the current state
(terminal state, wrong stage, or unknown event), return
`{:error, :invalid_transition, current_state, event}`. The
`:invalid_transition` check takes precedence over the guard check.

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
    # TODO
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