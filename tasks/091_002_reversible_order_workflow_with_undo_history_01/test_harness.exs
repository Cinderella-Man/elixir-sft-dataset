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
    rec = full_path_completed()
    assert rec.state == :completed
    {:ok, back} = Workflow.undo(rec)
    assert back.state == :in_progress
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
end
