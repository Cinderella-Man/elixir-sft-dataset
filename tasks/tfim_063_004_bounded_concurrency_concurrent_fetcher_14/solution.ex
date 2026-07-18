  test "a fetch killed from outside does not crash a non-trapping caller" do
    parent = self()

    {caller, ref} =
      spawn_monitor(fn ->
        sources = [
          {:killed, fn -> Process.exit(self(), :kill) end},
          {:healthy, fn -> {:ok, :done} end}
        ]

        send(parent, {:result, PooledFetcher.fetch_all(sources, 2, 1_000)})
      end)

    assert_receive {:result, result}, 2_000
    assert result[:killed] == {:error, :killed}
    assert result[:healthy] == {:ok, :done}
    assert_receive {:DOWN, ^ref, :process, ^caller, :normal}, 1_000
  end