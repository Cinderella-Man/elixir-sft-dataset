  test "non-strict type mismatch is NOT a conflict; override wins" do
    base = %{port: 5432}
    override = %{port: "5433"}

    assert {:ok, merged} = StrictConfigMerger.merge(base, override, strict: false)
    assert merged.port == "5433"
  end