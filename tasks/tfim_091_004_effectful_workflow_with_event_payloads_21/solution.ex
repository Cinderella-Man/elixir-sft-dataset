  test "reject guard rejects nil and non-binary reasons in the payload" do
    rec = submitted()

    for bad <- [%{reason: nil}, %{reason: 123}, %{reason: :duplicate}, %{reason: ["a"]}] do
      assert {:error, :guard_failed, :submitted, :reject} =
               Workflow.transition(rec, :reject, bad)

      assert Workflow.can?(rec, :reject, bad) == false
    end

    refute Map.has_key?(rec, :rejection_reason)
  end