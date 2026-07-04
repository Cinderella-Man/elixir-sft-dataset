  test "handles error returns and crashes without affecting other fetches" do
    sources = [
      {:ok_src, slow_ok(:a, 10)},
      {:err, slow_error(:bad, 10)},
      {:boom, slow_raise("x", 10)}
    ]

    result = PooledFetcher.fetch_all(sources, 3, 1_000)

    assert result[:ok_src] == {:ok, :a}
    assert result[:err] == {:error, :bad}
    assert {:error, %RuntimeError{message: "x"}} = result[:boom]
  end