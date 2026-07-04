  test "strict scalar type mismatch is a conflict" do
    base = %{port: 5432}
    override = %{port: "5433"}

    assert {:error, [conflict]} = StrictConfigMerger.merge(base, override, strict: true)
    assert conflict.type == :type_mismatch
    assert conflict.path == [:port]
    assert conflict.base == 5432
    assert conflict.override == "5433"
  end