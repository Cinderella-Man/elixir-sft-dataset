# Implement `transition/3`

Implement the public `transition/3` function, the workhorse of the state
machine. It takes a `record` (a map containing a `:state` key), an `event` atom,
and a `payload` map, and attempts to apply the event.

Its behavior must be:

- Look the `event` up in the `@transitions` table. Each entry maps an event to a
  `{from, to}` tuple.
- If the event exists **and** its `from` state matches the record's current
  `:state`, the edge is valid. Otherwise — the event is unknown, or its `from`
  does not match the current state (wrong stage or a terminal state) — return
  `{:error, :invalid_transition, current_state, event}`. This
  `:invalid_transition` check takes precedence over the guard check.
- For a valid edge, run the event's `guard/3`. If the guard rejects, return
  `{:error, :guard_failed, current_state, event}` and leave the record
  unchanged.
- If the guard passes, build the updated record by replacing `:state` with the
  destination `to` and then applying the event's `effect/3` (which stamps
  payload-derived data onto the record, preserving untouched fields). Return
  `{:ok, updated_record}`.

The `payload` argument defaults to `%{}`, and the implementing clause pattern-
matches the record's `:state` and guards on `is_map(payload)`.

```elixir
defmodule Workflow do
  @moduledoc """
  A finite state machine for an order lifecycle where each transition carries an
  event payload. Guards may inspect that payload, and successful transitions run
  effects that stamp payload-derived data onto the record.

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
    Map.put(attrs, :state, :draft)
  end

  @spec states() :: [atom()]
  def states, do: @states

  @spec transition(map(), atom(), map()) ::
          {:ok, map()}
          | {:error, :invalid_transition, atom(), atom()}
          | {:error, :guard_failed, atom(), atom()}
  def transition(record, event, payload \\ %{})

  def transition(%{state: current} = record, event, payload) when is_map(payload) do
    # TODO
  end

  @spec can?(map(), atom(), map()) :: boolean()
  def can?(record, event, payload \\ %{}) do
    match?({:ok, _}, transition(record, event, payload))
  end

  # Guards: return true when the transition is permitted.

  defp guard(:submit, %{items: items}, _payload) when is_list(items) and items != [], do: true
  defp guard(:submit, _record, _payload), do: false

  defp guard(:approve, _record, %{approver: a}) when is_binary(a) and a != "", do: true
  defp guard(:approve, _record, _payload), do: false

  defp guard(:reject, _record, %{reason: r}) when is_binary(r) and r != "", do: true
  defp guard(:reject, _record, _payload), do: false

  defp guard(_event, _record, _payload), do: true

  # Effects: applied after the state change on success.

  defp effect(record, :approve, %{approver: a}), do: Map.put(record, :approved_by, a)

  defp effect(record, :reject, %{reason: r}), do: Map.put(record, :rejection_reason, r)

  defp effect(record, :complete, _payload), do: Map.put(record, :completed, true)

  defp effect(record, :cancel, %{reason: r}) when is_binary(r),
    do: Map.put(record, :cancelled_reason, r)

  defp effect(record, _event, _payload), do: record
end
```