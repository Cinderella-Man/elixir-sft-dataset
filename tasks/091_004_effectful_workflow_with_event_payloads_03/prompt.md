Implement the private `guard/3` function. It is called as `guard(event, record, payload)`
and returns a boolean saying whether the given transition is permitted; `transition/3`
only applies the state change and effect when it returns `true`.

Encode exactly these guards, and let every other event pass unconditionally:

- **`:submit`** — inspect the **record** (ignore the payload): pass only when the
  record's `:items` field is a non-empty list.
- **`:approve`** — inspect the **payload** (ignore the record): pass only when the
  payload's `:approver` key is a non-empty binary. A missing key, `nil`, the empty
  string, or any non-binary value must fail.
- **`:reject`** — inspect the **payload**: pass only when the payload's `:reason`
  key is a non-empty binary, with the same failure rules as `:approve`.
- **Any other event** (e.g. `:start`, `:complete`, `:cancel`) — always pass.

Prefer clause-level pattern matching plus guards (`is_list/1`, `is_binary/1`, and
inequality checks) over conditional logic inside a single clause, and make sure a
catch-all clause returns `true`.

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

  defp guard(event, record, payload) do
    # TODO
  end

  # Effects: applied after the state change on success.

  defp effect(record, :approve, %{approver: a}), do: Map.put(record, :approved_by, a)

  defp effect(record, :reject, %{reason: r}), do: Map.put(record, :rejection_reason, r)

  defp effect(record, :complete, _payload), do: Map.put(record, :completed, true)

  defp effect(record, :cancel, %{reason: r}) when is_binary(r),
    do: Map.put(record, :cancelled_reason, r)

  defp effect(record, _event, _payload), do: record
end
```