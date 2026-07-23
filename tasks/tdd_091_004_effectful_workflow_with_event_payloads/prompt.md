# Implement to green

Treat the ExUnit suite below as the full requirements document. Write the
code under test so the whole suite passes. Dependencies: only what the
tests already use (the standard library and OTP otherwise). Style:
`@moduledoc`, `@doc` + `@spec` on the public API, warning-free compile.

## The test suite

```elixir
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

  test "invalid edge reports invalid_transition even when the guard would fail" do
    rec = draft()

    assert {:error, :invalid_transition, :draft, :approve} =
             Workflow.transition(rec, :approve, %{})

    assert {:error, :invalid_transition, :draft, :reject} =
             Workflow.transition(rec, :reject, %{reason: ""})

    {:ok, rejected} = Workflow.transition(submitted(), :reject, %{reason: "dup"})

    assert {:error, :invalid_transition, :rejected, :approve} =
             Workflow.transition(rejected, :approve, %{approver: nil})
  end

  test "rejected and cancelled records built via the API reject every event" do
    {:ok, rejected} = Workflow.transition(submitted(), :reject, %{reason: "dup"})

    {:ok, rec} = Workflow.transition(submitted(), :approve, %{approver: "m"})
    {:ok, rec} = Workflow.transition(rec, :start)
    {:ok, cancelled} = Workflow.transition(rec, :cancel, %{reason: "stop"})

    events = [:submit, :approve, :reject, :start, :complete, :cancel]

    for event <- events do
      assert {:error, :invalid_transition, :rejected, ^event} =
               Workflow.transition(rejected, event, %{approver: "x", reason: "y"})

      assert {:error, :invalid_transition, :cancelled, ^event} =
               Workflow.transition(cancelled, event, %{approver: "x", reason: "y"})

      assert Workflow.can?(rejected, event, %{approver: "x", reason: "y"}) == false
      assert Workflow.can?(cancelled, event, %{approver: "x", reason: "y"}) == false
    end
  end

  test "cancel with a non-binary reason succeeds without stamping cancelled_reason" do
    rec = Workflow.new(%{items: [:a], note: "keep"})
    {:ok, rec} = Workflow.transition(rec, :submit)
    {:ok, rec} = Workflow.transition(rec, :approve, %{approver: "m"})
    {:ok, rec} = Workflow.transition(rec, :start)

    {:ok, done} = Workflow.transition(rec, :cancel, %{reason: 123})
    assert done.state == :cancelled
    refute Map.has_key?(done, :cancelled_reason)
    assert done.note == "keep"
    assert done.items == [:a]

    {:ok, done2} = Workflow.transition(rec, :cancel, %{reason: nil})
    assert done2.state == :cancelled
    refute Map.has_key?(done2, :cancelled_reason)
  end

  test "reject guard rejects nil and non-binary reasons in the payload" do
    rec = submitted()

    for bad <- [%{reason: nil}, %{reason: 123}, %{reason: :duplicate}, %{reason: ["a"]}] do
      assert {:error, :guard_failed, :submitted, :reject} =
               Workflow.transition(rec, :reject, bad)

      assert Workflow.can?(rec, :reject, bad) == false
    end

    refute Map.has_key?(rec, :rejection_reason)
  end

  test "approve, reject and complete effects preserve untouched fields" do
    base = Workflow.new(%{items: [:a], note: "hi", meta: %{c: "acme"}})
    {:ok, sub} = Workflow.transition(base, :submit)

    {:ok, rej} = Workflow.transition(sub, :reject, %{reason: "dup"})
    assert rej.rejection_reason == "dup"
    assert rej.note == "hi"
    assert rej.meta == %{c: "acme"}
    assert rej.items == [:a]

    {:ok, rec} = Workflow.transition(sub, :approve, %{approver: "manager"})
    assert rec.approved_by == "manager"
    assert rec.note == "hi"
    assert rec.meta == %{c: "acme"}

    {:ok, rec} = Workflow.transition(rec, :start)
    {:ok, rec} = Workflow.transition(rec, :complete, %{approver: "ignored"})
    assert rec.completed == true
    assert rec.approved_by == "manager"
    assert rec.note == "hi"
    assert rec.items == [:a]
  end

  test "can?/3 is false for wrong-stage and unknown events" do
    rec = draft()

    assert Workflow.can?(rec, :approve, %{approver: "m"}) == false
    assert Workflow.can?(rec, :complete) == false
    assert Workflow.can?(rec, :teleport, %{approver: "m"}) == false
    assert Workflow.can?(Workflow.new(%{items: []}), :submit) == false
    assert Workflow.can?(rec, :submit, %{ignored: 1}) == true
  end
end
```

Deliverable: the module(s) alone in a single file — not the tests.
