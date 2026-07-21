# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule WorkflowTest do
  use ExUnit.Case, async: false

  defp submittable_draft do
    Workflow.new(%{items: [:widget], approved_by: "manager", note: "hello"})
  end

  defp full_path_completed do
    rec = submittable_draft()
    {:ok, rec} = Workflow.transition(rec, :submit)
    {:ok, rec} = Workflow.transition(rec, :approve)
    {:ok, rec} = Workflow.transition(rec, :start)
    {:ok, rec} = Workflow.transition(rec, :complete)
    rec
  end

  defp in_progress_order do
    rec = submittable_draft()
    {:ok, rec} = Workflow.transition(rec, :submit)
    {:ok, rec} = Workflow.transition(rec, :approve)
    {:ok, rec} = Workflow.transition(rec, :start)
    rec
  end

  # -------------------------------------------------------
  # Construction
  # -------------------------------------------------------

  test "new/0 starts in :draft with empty history" do
    rec = Workflow.new()
    assert rec.state == :draft
    assert rec.history == []
  end

  test "new/1 merges attrs and forces draft + empty history" do
    rec = Workflow.new(%{items: [1], state: :completed, history: [:garbage], tag: 7})
    assert rec.state == :draft
    assert rec.history == []
    assert rec.items == [1]
    assert rec.tag == 7
  end

  test "states/0 lists all seven states" do
    states = Workflow.states()

    for s <- [:draft, :submitted, :approved, :in_progress, :completed, :rejected, :cancelled] do
      assert s in states
    end

    assert length(Enum.uniq(states)) == 7
  end

  # -------------------------------------------------------
  # Forward walk + history tracking
  # -------------------------------------------------------

  test "walks the full happy path and records history" do
    rec = full_path_completed()
    assert rec.state == :completed
    assert Workflow.history(rec) == [:submit, :approve, :start, :complete]
  end

  test "history/1 is chronological and side branches are recorded" do
    rec = submittable_draft()
    {:ok, rec} = Workflow.transition(rec, :submit)
    {:ok, rec} = Workflow.transition(rec, :reject)
    assert rec.state == :rejected
    assert Workflow.history(rec) == [:submit, :reject]
  end

  test "transition preserves unrelated fields" do
    rec = Workflow.new(%{items: [:a], meta: %{customer: "acme"}})
    {:ok, rec} = Workflow.transition(rec, :submit)
    assert rec.meta == %{customer: "acme"}
    assert rec.items == [:a]
  end

  # -------------------------------------------------------
  # The :cancel side branch
  # -------------------------------------------------------

  test "cancel moves :in_progress to :cancelled, records it, and stays undoable" do
    rec = in_progress_order()
    assert rec.state == :in_progress

    {:ok, cancelled} = Workflow.transition(rec, :cancel)
    assert cancelled.state == :cancelled
    assert Workflow.history(cancelled) == [:submit, :approve, :start, :cancel]
    assert cancelled.note == "hello"

    for event <- [:submit, :approve, :reject, :start, :complete, :cancel] do
      assert {:error, :invalid_transition, :cancelled, ^event} =
               Workflow.transition(cancelled, event)
    end

    {:ok, back} = Workflow.undo(cancelled)
    assert back.state == :in_progress
    assert Workflow.history(back) == [:submit, :approve, :start]
  end

  test "cancel carries no guard and fires regardless of items/approved_by" do
    hostile = %{in_progress_order() | items: [], approved_by: ""}
    assert {:ok, %{state: :cancelled}} = Workflow.transition(hostile, :cancel)
  end

  test "can?/2 permits :cancel only from :in_progress" do
    draft = submittable_draft()
    {:ok, submitted} = Workflow.transition(draft, :submit)
    {:ok, approved} = Workflow.transition(submitted, :approve)
    {:ok, started} = Workflow.transition(approved, :start)
    {:ok, completed} = Workflow.transition(started, :complete)

    assert Workflow.can?(draft, :cancel) == false
    assert Workflow.can?(submitted, :cancel) == false
    assert Workflow.can?(approved, :cancel) == false
    assert Workflow.can?(started, :cancel) == true
    assert Workflow.can?(completed, :cancel) == false

    {:ok, cancelled} = Workflow.transition(started, :cancel)
    assert Workflow.can?(cancelled, :cancel) == false
  end

  test ":complete and :cancel lead to different destinations from :in_progress" do
    rec = in_progress_order()
    {:ok, completed} = Workflow.transition(rec, :complete)
    {:ok, cancelled} = Workflow.transition(rec, :cancel)
    assert completed.state == :completed
    assert cancelled.state == :cancelled
  end

  # -------------------------------------------------------
  # Undo
  # -------------------------------------------------------

  test "undo reverts a single transition and trims history" do
    rec = submittable_draft()
    {:ok, submitted} = Workflow.transition(rec, :submit)
    assert submitted.state == :submitted

    {:ok, back} = Workflow.undo(submitted)
    assert back.state == :draft
    assert Workflow.history(back) == []
  end

  test "undo can be applied repeatedly, unwinding the path" do
    rec = full_path_completed()

    {:ok, rec} = Workflow.undo(rec)
    assert rec.state == :in_progress
    assert Workflow.history(rec) == [:submit, :approve, :start]

    {:ok, rec} = Workflow.undo(rec)
    assert rec.state == :approved

    {:ok, rec} = Workflow.undo(rec)
    assert rec.state == :submitted

    {:ok, rec} = Workflow.undo(rec)
    assert rec.state == :draft
    assert Workflow.history(rec) == []
  end

  test "undo works from a terminal state" do
    # TODO
  end

  test "undo on empty history returns nothing_to_undo" do
    rec = submittable_draft()
    assert Workflow.undo(rec) == {:error, :nothing_to_undo}
  end

  test "undo preserves unrelated domain fields" do
    rec = Workflow.new(%{items: [:a], approved_by: "m", tag: 99})
    {:ok, rec} = Workflow.transition(rec, :submit)
    {:ok, rec} = Workflow.undo(rec)
    assert rec.tag == 99
    assert rec.items == [:a]
  end

  # -------------------------------------------------------
  # Invalid transitions
  # -------------------------------------------------------

  test "invalid event from draft returns invalid_transition" do
    rec = submittable_draft()

    assert {:error, :invalid_transition, :draft, :approve} =
             Workflow.transition(rec, :approve)

    assert {:error, :invalid_transition, :draft, :teleport} =
             Workflow.transition(rec, :teleport)
  end

  test "terminal states reject every forward event" do
    rec = full_path_completed()

    for event <- [:submit, :approve, :reject, :start, :complete, :cancel] do
      assert {:error, :invalid_transition, :completed, ^event} =
               Workflow.transition(rec, event)
    end
  end

  # -------------------------------------------------------
  # Guards
  # -------------------------------------------------------

  test "submit guard fails on empty/missing/non-list items" do
    for items <- [[], "no", nil] do
      rec = Workflow.new(%{items: items})
      assert {:error, :guard_failed, :draft, :submit} = Workflow.transition(rec, :submit)
    end

    missing = Workflow.new(%{})
    assert {:error, :guard_failed, :draft, :submit} = Workflow.transition(missing, :submit)
  end

  test "approve guard checks approved_by string" do
    rec = submittable_draft()
    {:ok, submitted} = Workflow.transition(rec, :submit)

    assert {:ok, %{state: :approved}} = Workflow.transition(submitted, :approve)

    bad = %{submitted | approved_by: ""}
    assert {:error, :guard_failed, :submitted, :approve} = Workflow.transition(bad, :approve)
  end

  test "guard failure leaves the record and history unchanged" do
    rec = Workflow.new(%{items: []})
    assert {:error, :guard_failed, :draft, :submit} = Workflow.transition(rec, :submit)
    assert rec.state == :draft
    assert rec.history == []
  end

  # -------------------------------------------------------
  # can?/2
  # -------------------------------------------------------

  test "can?/2 reflects valid edges and guards without mutating" do
    ok = submittable_draft()
    bad = Workflow.new(%{items: []})

    assert Workflow.can?(ok, :submit) == true
    assert Workflow.can?(bad, :submit) == false
    assert Workflow.can?(ok, :approve) == false

    # not mutated
    assert ok.state == :draft
    assert ok.history == []
  end

  test "undo succeeds even when the original transition's guard would now fail" do
    rec = Workflow.new(%{items: [:widget], approved_by: "manager"})
    {:ok, submitted} = Workflow.transition(rec, :submit)
    {:ok, approved} = Workflow.transition(submitted, :approve)

    guard_hostile = %{approved | items: [], approved_by: ""}

    {:ok, back_to_submitted} = Workflow.undo(guard_hostile)
    assert back_to_submitted.state == :submitted
    assert Workflow.history(back_to_submitted) == [:submit]

    {:ok, back_to_draft} = Workflow.undo(back_to_submitted)
    assert back_to_draft.state == :draft
    assert Workflow.history(back_to_draft) == []
  end
end
```
