  test "locked key preserves the earlier value and provenance" do
    layers = [
      {:base, %{secret: "s3cr3t", other: "base"}},
      {:env, %{secret: "pwned", other: "new"}}
    ]

    result = LayeredConfig.merge(layers, locked: [[:secret]])

    assert result.config.secret == "s3cr3t"
    assert result.config.other == "new"
    assert result.provenance[[:secret]] == :base
    assert result.provenance[[:other]] == :env
  end