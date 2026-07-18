  test "atom and boolean scalars are replaced including false values" do
    base = %{mode: :production, debug: true, verbose: false}
    override = %{mode: :staging, debug: false, verbose: true}

    result = ConfigMerger.merge(base, override)

    assert result.mode == :staging
    assert result.debug == false
    assert result.verbose == true
  end