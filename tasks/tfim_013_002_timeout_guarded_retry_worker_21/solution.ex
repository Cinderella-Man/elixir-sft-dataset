  test "registers under the :name option and serves calls addressed by that name" do
    {:ok, _pid} =
      TimeoutRetryWorker.start_link(
        name: :trw_named_worker,
        random: &ZeroRandom.rand/1
      )

    assert {:ok, :via_name} =
             TimeoutRetryWorker.execute(:trw_named_worker, fn -> {:ok, :via_name} end,
               max_retries: 0
             )
  end