  test "a queued element does not start while a timed-out element is retrying" do
    parent = self()

    spawn(fn ->
      out =
        RetryMap.pmap(
          [1, 2],
          fn
            1 ->
              Process.sleep(1000)
              :never

            2 ->
              send(parent, :second_started)
              20
          end,
          max_concurrency: 1,
          timeout: 100,
          max_attempts: 2
        )

      send(parent, {:pmap_done, out})
    end)

    refute_receive :second_started, 150
    assert_receive :second_started, 1000
    assert_receive {:pmap_done, [{:error, :timeout}, {:ok, 20}]}, 1000
  end