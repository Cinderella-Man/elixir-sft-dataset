  test "strict structural mismatch (map vs scalar) is a conflict" do
    base = %{db: %{host: "localhost"}}
    override = %{db: "disabled"}

    assert {:error, [conflict]} = StrictConfigMerger.merge(base, override, strict: true)
    assert conflict.type == :type_mismatch
    assert conflict.path == [:db]
  end