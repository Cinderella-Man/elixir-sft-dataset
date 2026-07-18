  test "a timed-out attempt is really killed and produces no late side effect" do
    parent = self()

    results =
      RetryMap.pmap(
        [1],
        fn x ->
          Process.sleep(300)
          send(parent, {:late, x})
          x
        end,
        max_concurrency: 1,
        timeout: 60,
        max_attempts: 1
      )

    assert results == [{:error, :timeout}]
    refute_receive {:late, 1}, 500
  end