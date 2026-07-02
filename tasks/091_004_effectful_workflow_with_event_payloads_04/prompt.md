# Implement `effect/3`

You are completing the `Workflow` module below. Every function is already
implemented **except** the private `effect/3` function, whose body has been
replaced with `# TODO`. Implement it.

`effect/3` is called by `transition/3` *after* the record's `:state` has already
been updated to the destination state, on a successful transition only. Its job
is to stamp payload-derived domain data onto the record according to the event.
It takes the (already state-updated) `record`, the `event` atom, and the
`payload` map, and returns the record with the event's effect applied.

Implement exactly these effects:

- **`:approve`**: set `:approved_by` to the payload's `:approver`.
- **`:reject`**: set `:rejection_reason` to the payload's `:reason`.
- **`:complete`**: set `:completed` to `true` (the payload is ignored).
- **`:cancel`**: if the payload has a binary `:reason`, set `:cancelled_reason`
  to it; otherwise leave the record's fields unchanged.
- **All other events** (e.g. `:submit`, `:start`): no effect beyond the state
  change already applied — return the record unchanged.

Fields not written by the effect must be preserved.

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
    case Map.fetch(@transitions, event) do
      {:ok, {^current, to}} ->
        if guard(event, record, payload) do
          updated =
            record
            |> Map.put(:state, to)
            |> effect(event, payload)

          {:ok, updated}
        else
          {:error, :guard_failed, current, event}
        end

      _ ->
        {:error, :invalid_transition, current, event}
    end
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

  defp effect(record, event, payload) do
    # TODO
  end
end
```

Return your answer as one or more file blocks and NOTHING ELSE — no prose, no
markdown fences around the blocks. Each file must be exactly:

<file path="RELATIVE/PATH">
…verbatim file contents…