  test "reports all_failed with the ordered list of reasons when every fallback fails" do
    result =
      FallbackFetcher.fetch_all(
        [{:a, [fast_error(:one), fast_error(:two), fast_raise("three")]}],
        1_000
      )

    assert {:error, {:all_failed, reasons}} = result[:a]
    assert length(reasons) == 3
    assert Enum.at(reasons, 0) == :one
    assert Enum.at(reasons, 1) == :two
    assert %RuntimeError{message: "three"} = Enum.at(reasons, 2)
  end