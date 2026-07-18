  test "tuple key paths work for locked and list_strategies options" do
    layers = [
      {:base, %{db: %{password: "keep", tags: ["a"]}}},
      {:env, %{db: %{password: "hack", tags: ["b"]}}}
    ]

    result =
      LayeredConfig.merge(layers,
        locked: [{:db, :password}],
        list_strategies: %{{:db, :tags} => :append}
      )

    assert result.config.db.password == "keep"
    assert result.config.db.tags == ["a", "b"]
    assert result.provenance[[:db, :password]] == :base
    assert result.provenance[[:db, :tags]] == [:base, :env]
  end