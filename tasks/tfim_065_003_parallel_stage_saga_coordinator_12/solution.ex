  test "steps within a stage are started before any of them completes" do
    parent = self()

    rendezvous = fn name ->
      fn _ctx ->
        send(parent, {:started, name, self()})

        receive do
          :go -> {:ok, name}
        after
          2_000 -> {:error, :never_released}
        end
      end
    end

    saga =
      ParallelSaga.new()
      |> ParallelSaga.stage([
        {:a, rendezvous.(:a), comp(:a)},
        {:b, rendezvous.(:b), comp(:b)}
      ])

    runner = Task.async(fn -> ParallelSaga.execute(saga, %{}) end)

    assert_receive {:started, :a, pid_a}, 1_000
    assert_receive {:started, :b, pid_b}, 1_000

    send(pid_a, :go)
    send(pid_b, :go)

    assert {:ok, %{a: :a, b: :b}} = Task.await(runner, 5_000)
  end