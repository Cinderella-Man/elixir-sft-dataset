  test "deep merge returns :ok" do
    base = %{db: %{host: "localhost", port: 5432, name: "prod"}}
    override = %{db: %{port: 5433}}

    assert {:ok, merged} = StrictConfigMerger.merge(base, override)
    assert merged.db == %{host: "localhost", port: 5433, name: "prod"}
  end