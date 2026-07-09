  test "an element that always times out returns {:error, :timeout} after exhausting attempts" do
    results =
      RetryMap.pmap(
        [1],
        fn _ ->
          Process.sleep(500)
          :never
        end,
        max_concurrency: 1,
        timeout: 80,
        max_attempts: 2
      )

    assert results == [{:error, :timeout}]
  end