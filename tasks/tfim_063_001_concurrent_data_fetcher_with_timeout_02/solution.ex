  test "returns ok for all fast fetches" do
    sources = [
      {:a, slow_ok(:result_a, 10)},
      {:b, slow_ok(:result_b, 20)},
      {:c, slow_ok(:result_c, 5)}
    ]

    result = ConcurrentFetcher.fetch_all(sources, 500)

    assert result == %{
             a: {:ok, :result_a},
             b: {:ok, :result_b},
             c: {:ok, :result_c}
           }
  end