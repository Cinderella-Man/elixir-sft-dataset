# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `new` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Reversible Order Workflow with Undo & History

Write me an Elixir module called `Workflow` that defines and enforces a finite
state machine for the lifecycle of an order **and records every applied
transition so it can be undone**.

## States

Same lifecycle as a plain order workflow:

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

`:completed`, `:rejected`, and `:cancelled` are **terminal** for *forward*
transitions — no event can move an order out of them. (Undo, described below,
is not a forward transition and *can* leave a terminal state.)

## Transition table

Each event is an atom and maps to exactly one `from → to` edge:

| event       | from          | to            |
|-------------|---------------|---------------|
| `:submit`   | `:draft`      | `:submitted`  |
| `:approve`  | `:submitted`  | `:approved`   |
| `:reject`   | `:submitted`  | `:rejected`   |
| `:start`    | `:approved`   | `:in_progress`|
| `:complete` | `:in_progress`| `:completed`  |
| `:cancel`   | `:in_progress`| `:cancelled`  |

## The record

A *record* is a plain map that always contains:

- a `:state` key holding the current state atom, and
- a `:history` key holding a list of the transitions applied so far.

Any other domain fields must be preserved untouched across transitions and
undos.

## Public API

- `Workflow.new(attrs \\ %{})` — build a new record. Returns `attrs` merged with
  `%{state: :draft, history: []}`. Both `:state` and `:history` provided in
  `attrs` (if any) are overridden — a new record always starts in `:draft` with
  an empty history. `attrs` is a map with atom keys.

- `Workflow.states/0` — return the list of all seven state atoms.

- `Workflow.transition(record, event)` — attempt a **forward** transition.
  - On success, return `{:ok, updated_record}` where `:state` is replaced by the
    destination state, a history entry is recorded (see below), and all other
    fields are preserved.
  - If `event` is not a valid transition out of the current state (terminal
    state, wrong stage, or unknown event), return
    `{:error, :invalid_transition, current_state, event}`.
  - If the event is a valid edge but its guard rejects the record, return
    `{:error, :guard_failed, current_state, event}` and leave the record
    unchanged. `:invalid_transition` takes precedence over the guard check.

- `Workflow.undo(record)` — revert the most recently applied transition.
  - If the history is empty, return `{:error, :nothing_to_undo}`.
  - Otherwise return `{:ok, updated_record}` with `:state` set back to the
    `from` state of the most recent entry and that entry removed from the
    history. Undo does **not** re-run guards, and it works even from a terminal
    state. Undo reverts only the `:state`; other domain fields are left as they
    are.

- `Workflow.history(record)` — return the list of event atoms that have been
  applied (and not undone), in **chronological order** (oldest first).

- `Workflow.can?(record, event)` — return `true` if
  `Workflow.transition(record, event)` would succeed, otherwise `false`.

## Guards

Encode exactly these two guards; all other transitions always pass:

- **`:submit`** (`:draft → :submitted`): passes only when the record's `:items`
  field is a non-empty list.

- **`:approve`** (`:submitted → :approved`): passes only when the record's
  `:approved_by` field is a non-empty binary (string).

## History entries

Each recorded history entry is a `{event, from_state, to_state}` tuple. You may
store the list in whatever internal order is convenient (e.g. most-recent
first), as long as `undo/1` reverts the latest transition and `history/1`
returns events oldest-first.

## Constraints

- Single file, module named `Workflow`.
- Use only the Elixir/OTP standard library — no external dependencies.
- No processes are required; this is a pure functional module.

## The module with `new` missing

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

  def new(attrs \\ %{}) when is_map(attrs) do
    # TODO
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
  defp guard(:submit, %{items: items}) when is_list(items) and items != [], do: true
  defp guard(:submit, _record), do: false

  defp guard(:approve, %{approved_by: approved_by})
       when is_binary(approved_by) and approved_by != "",
       do: true

  defp guard(:approve, _record), do: false

  defp guard(_event, _record), do: true
end
```

Give me only the complete implementation of `new` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
