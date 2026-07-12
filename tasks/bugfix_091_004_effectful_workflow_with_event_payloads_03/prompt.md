# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

# Effectful Workflow with Event Payloads

Write me an Elixir module called `Workflow` that enforces the order lifecycle
state machine **and threads an event payload through each transition**, so that
guards can inspect the payload and transitions can apply *effects* that stamp
domain data onto the record.

## States

```
draft → submitted → approved → in_progress → completed
```

with two side branches:

```
submitted → rejected
in_progress → cancelled
```

The full set of states is:

`:draft`, `:submitted`, `:approved`, `:in_progress`, `:completed`,
`:rejected`, `:cancelled`.

`:completed`, `:rejected`, and `:cancelled` are **terminal** — no event can move
an order out of them.

## Transition table

| event       | from          | to            |
|-------------|---------------|---------------|
| `:submit`   | `:draft`      | `:submitted`  |
| `:approve`  | `:submitted`  | `:approved`   |
| `:reject`   | `:submitted`  | `:rejected`   |
| `:start`    | `:approved`   | `:in_progress`|
| `:complete` | `:in_progress`| `:completed`  |
| `:cancel`   | `:in_progress`| `:cancelled`  |

## The record

A *record* is a plain map that always contains a `:state` key holding the
current state atom, plus any additional domain fields. Fields not touched by an
effect must be preserved across a transition.

## Public API

- `Workflow.new(attrs \\ %{})` — build a new record. Returns `attrs` merged with
  `%{state: :draft}` (any `:state` in `attrs` is overridden). `attrs` is a map
  with atom keys.

- `Workflow.states/0` — return the list of all seven state atoms.

- `Workflow.transition(record, event, payload \\ %{})` — attempt to apply
  `event` with an accompanying `payload` map.
  - On success, return `{:ok, updated_record}` where `:state` is replaced by the
    destination **and** the event's effect (if any) has been applied. Fields not
    written by the effect are preserved.
  - If `event` is not a valid transition out of the current state (terminal
    state, wrong stage, or unknown event), return
    `{:error, :invalid_transition, current_state, event}`.
  - If the event is a valid edge but its guard rejects the record/payload,
    return `{:error, :guard_failed, current_state, event}` and leave the record
    unchanged. `:invalid_transition` takes precedence over the guard check.

- `Workflow.can?(record, event, payload \\ %{})` — return `true` if
  `Workflow.transition(record, event, payload)` would succeed, otherwise
  `false`.

## Guards

Encode exactly these guards; all other transitions always pass:

- **`:submit`** (`:draft → :submitted`): passes only when the **record's**
  `:items` field is a non-empty list. (Record-based, ignores the payload.)

- **`:approve`** (`:submitted → :approved`): passes only when the **payload's**
  `:approver` key is a non-empty binary (string). A missing key, `nil`, the
  empty string, or a non-binary all fail.

- **`:reject`** (`:submitted → :rejected`): passes only when the **payload's**
  `:reason` key is a non-empty binary (string). Same failure rules as above.

## Effects

On a successful transition, after the state is updated, the event's effect (if
any) writes payload-derived data into the record:

- **`:approve`**: set `:approved_by` to the payload's `:approver`.
- **`:reject`**: set `:rejection_reason` to the payload's `:reason`.
- **`:complete`**: set `:completed` to `true` (payload ignored).
- **`:cancel`**: if the payload has a binary `:reason`, set `:cancelled_reason`
  to it; otherwise leave the record's fields unchanged (cancel has no guard).
- All other events (`:submit`, `:start`): no effect beyond the state change.

## Constraints

- Single file, module named `Workflow`.
- Use only the Elixir/OTP standard library — no external dependencies.
- No processes are required; this is a pure functional module.

## The buggy module

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

  @doc "Builds a new effectful workflow from `attrs`. Returns the workflow map."
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

          {:error, updated}
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

  defp effect(record, :approve, %{approver: a}), do: Map.put(record, :approved_by, a)

  defp effect(record, :reject, %{reason: r}), do: Map.put(record, :rejection_reason, r)

  defp effect(record, :complete, _payload), do: Map.put(record, :completed, true)

  defp effect(record, :cancel, %{reason: r}) when is_binary(r),
    do: Map.put(record, :cancelled_reason, r)

  defp effect(record, _event, _payload), do: record
end
```

## Failing test report

```
11 of 16 test(s) failed:

  * test full happy path applies payload effects
      
      
      match (=) failed
      code:  assert {:ok, rec} = Workflow.transition(rec, :submit)
      left:  {:ok, rec}
      right: {:error, %{state: :submitted, items: [:widget], note: "hi"}}
      

  * test reject stamps the rejection reason from the payload
      no match of right hand side value:
      
          {:error, %{state: :submitted, items: [:widget], note: "hi"}}
      

  * test cancel with a reason stamps cancelled_reason
      no match of right hand side value:
      
          {:error, %{state: :submitted, items: [:widget], note: "hi"}}
      

  * test cancel without a reason still succeeds and adds no reason field
      no match of right hand side value:
      
          {:error, %{state: :submitted, items: [:widget], note: "hi"}}
      

  (…7 more)
```
