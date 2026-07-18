  test "conflicts across mismatch, lock, and required are all reported" do
    base = %{port: 1, secret: "keep"}
    override = %{port: "two", secret: "change"}

    assert {:error, conflicts} =
             StrictConfigMerger.merge(base, override,
               strict: true,
               locked: [[:secret]],
               required: [[:missing]]
             )

    types = conflicts |> Enum.map(& &1.type) |> Enum.sort()
    assert types == [:locked_violation, :missing_required, :type_mismatch]
  end