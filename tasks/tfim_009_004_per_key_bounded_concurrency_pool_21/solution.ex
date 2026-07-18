  test "crash frees slot and starts a caller already queued behind it" do
    {:ok, kp} = KeyedPool.start_link(max_concurrency: 1)
    parent = self()

    crasher =
      Task.async(fn ->
        KeyedPool.execute(kp, :k, fn ->
          send(parent, {:crasher_running, self()})

          receive do
            :go -> :ok
          after
            2_000 -> :ok
          end

          raise "boom"
        end)
      end)

    # The crashing function is now holding the only slot for :k.
    assert_receive {:crasher_running, func_pid}, 1_000

    queued =
      Task.async(fn ->
        KeyedPool.execute(kp, :k, fn ->
          send(parent, :queued_running)
          {:ok, :recovered}
        end)
      end)

    # This caller is queued behind the crasher and must not run yet.
    refute_receive :queued_running, 200

    # Let the crasher raise; its slot must free and the queued caller start next.
    send(func_pid, :go)

    assert_receive :queued_running, 1_000

    assert {:error, {:exception, %RuntimeError{message: "boom"}}} =
             Task.await(crasher, 5_000)

    assert {:ok, :recovered} = Task.await(queued, 5_000)
  end