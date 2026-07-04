  test "strict merge with matching types returns :ok" do
    base = %{port: 4000, name: "a"}
    override = %{port: 9000, name: "b"}

    assert {:ok, merged} = StrictConfigMerger.merge(base, override, strict: true)
    assert merged == %{port: 9000, name: "b"}
  end