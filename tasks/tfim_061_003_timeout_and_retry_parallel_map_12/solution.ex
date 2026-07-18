  test "a timeout in one element does not affect the others" do
    results =
      RetryMap.pmap(
        [1, 2, 3],
        fn
          2 ->
            Process.sleep(400)
            :never

          x ->
            x * 10
        end,
        max_concurrency: 3,
        timeout: 80,
        max_attempts: 1
      )

    assert results == [{:ok, 10}, {:error, :timeout}, {:ok, 30}]
  end