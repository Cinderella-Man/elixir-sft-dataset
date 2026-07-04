  test "three layers apply in increasing precedence" do
    layers = [
      {:default, %{level: :info, retries: 1}},
      {:file, %{level: :warn}},
      {:env, %{retries: 5}}
    ]

    result = LayeredConfig.merge(layers)

    assert result.config == %{level: :warn, retries: 5}
    assert result.provenance[[:level]] == :file
    assert result.provenance[[:retries]] == :env
  end