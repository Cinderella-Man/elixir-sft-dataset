defmodule WorkflowTest do
  use ExUnit.Case, async: false

  defp draft do
    Workflow.new(%{items: [:widget], note: "hi"})
  end

  defp submitted do
    {:ok, rec} = Workflow.transition(draft(), :submit)
    rec
  end

  # -------------------------------------------------------
  # Construction
  # -------------------------------------------------------

  test "new/0 starts in :draft" do
    assert %{state: :draft} = Workflow.new()
  end

  test "new/1 merges attrs and forces :draft" do
    rec = Workflow.new(%{items: [1], state: :completed, tag: 3})
    assert rec.state == :draft
    assert rec.items == [1]
    assert rec.tag == 3
  end

  test "states/0 lists all seven states" do
    states = Workflow.states()

    for s <- [:draft, :submitted, :approved, :in_progress, :completed, :rejected, :cancelled] do
      assert s in states
    end

    assert length(Enum.uniq(states)) == 7
  end

  # -------------------------------------------------------
  # Happy path with payloads + effects
  # -------------------------------------------------------

  test "full happy path applies payload effects" do
    rec = draft()

    assert {:ok, rec} = Workflow.transition(rec, :submit)
    assert rec.state == :submitted

    assert {:ok, rec} = Workflow.transition(rec, :approve, %{approver: "manager"})
    assert rec.state == :approved
    assert rec.approved_by == "manager"

    assert {:ok, rec} = Workflow.transition(rec, :start)
    assert rec.state == :in_progress

    assert {:ok, rec} = Workflow.transition(rec, :complete)
    assert rec.state == :completed
    assert rec.completed == true
  end

  test "reject stamps the rejection reason from the payload" do
    {:ok, rec} = Workflow.transition(submitted(), :reject, %{reason: "duplicate"})
    assert rec.state == :rejected
    assert rec.rejection_reason == "duplicate"
  end

  test "cancel with a reason stamps cancelled_reason" do
    rec = submitted()
    {:ok, rec} = Workflow.transition(rec, :approve, %{approver: "m"})
    {:ok, rec} = Workflow.transition(rec, :start)
    {:ok, rec} = Workflow.transition(rec, :cancel, %{reason: "customer changed mind"})
    assert rec.state == :cancelled
    assert rec.cancelled_reason == "customer changed mind"
  end

  test "cancel without a reason still succeeds and adds no reason field" do
    rec = submitted()
    {:ok, rec} = Workflow.transition(rec, :approve, %{approver: "m"})
    {:ok, rec} = Workflow.transition(rec, :start)
    {:ok, rec} = Workflow.transition(rec, :cancel)
    assert rec.state == :cancelled
    refute Map.has_key?(rec, :cancelled_reason)
  end

  test "transition preserves unrelated fields" do
    rec = Workflow.new(%{items: [:a], meta: %{c: "acme"}})
    {:ok, rec} = Workflow.transition(rec, :submit)
    assert rec.meta == %{c: "acme"}
    assert rec.items == [:a]
  end

  # -------------------------------------------------------
  # Guards driven by payload
  # -------------------------------------------------------

  test "approve guard requires a non-empty approver in the payload" do
    rec = submitted()

    for bad <- [%{}, %{approver: nil}, %{approver: ""}, %{approver: 123}] do
      assert {:error, :guard_failed, :submitted, :approve} =
               Workflow.transition(rec, :approve, bad)
    end

    assert {:ok, %{state: :approved}} =
             Workflow.transition(rec, :approve, %{approver: "ok"})
  end

  test "reject guard requires a non-empty reason in the payload" do
    rec = submitted()

    assert {:error, :guard_failed, :submitted, :reject} =
             Workflow.transition(rec, :reject, %{})

    assert {:error, :guard_failed, :submitted, :reject} =
             Workflow.transition(rec, :reject, %{reason: ""})

    assert {:ok, %{state: :rejected}} =
             Workflow.transition(rec, :reject, %{reason: "bad"})
  end

  test "submit guard is record-based and ignores the payload" do
    empty = Workflow.new(%{items: []})

    assert {:error, :guard_failed, :draft, :submit} =
             Workflow.transition(empty, :submit, %{whatever: 1})

    ok = Workflow.new(%{items: [:a]})
    assert {:ok, %{state: :submitted}} = Workflow.transition(ok, :submit)
  end

  test "guard failure leaves the record unchanged" do
    rec = submitted()

    assert {:error, :guard_failed, :submitted, :approve} =
             Workflow.transition(rec, :approve, %{})

    assert rec.state == :submitted
    refute Map.has_key?(rec, :approved_by)
  end

  # -------------------------------------------------------
  # Invalid transitions
  # -------------------------------------------------------

  test "wrong-stage and unknown events are invalid" do
    rec = draft()

    assert {:error, :invalid_transition, :draft, :approve} =
             Workflow.transition(rec, :approve, %{approver: "x"})

    assert {:error, :invalid_transition, :draft, :teleport} =
             Workflow.transition(rec, :teleport)
  end

  test "terminal states reject every event" do
    completed = %{Workflow.new(%{}) | state: :completed}

    for event <- [:submit, :approve, :reject, :start, :complete, :cancel] do
      assert {:error, :invalid_transition, :completed, ^event} =
               Workflow.transition(completed, event, %{approver: "x", reason: "y"})
    end
  end

  # -------------------------------------------------------
  # can?/3
  # -------------------------------------------------------

  test "can?/3 accounts for the payload" do
    rec = submitted()
    assert Workflow.can?(rec, :approve, %{approver: "m"}) == true
    assert Workflow.can?(rec, :approve, %{}) == false
    assert Workflow.can?(rec, :reject, %{reason: "r"}) == true
    assert Workflow.can?(rec, :reject) == false
  end

  test "can?/3 defaults payload to empty and does not mutate" do
    rec = draft()
    assert Workflow.can?(rec, :submit) == true
    assert rec.state == :draft
  end
end
