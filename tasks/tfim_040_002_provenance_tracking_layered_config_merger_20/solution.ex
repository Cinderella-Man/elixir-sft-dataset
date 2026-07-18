  test "merge result exposes exactly the config and provenance keys" do
    result = LayeredConfig.merge([{:base, %{a: 1}}, {:env, %{a: 2}}])

    assert result |> Map.keys() |> Enum.sort() == [:config, :provenance]
    assert map_size(result) == 2
  end