  test "a non-positive quorum never invokes any fetch function" do
    parent = self()

    probe = fn name ->
      fn ->
        send(parent, {:invoked, name})
        {:ok, name}
      end
    end

    sources = [{:a, probe.(:a)}, {:b, probe.(:b)}]

    assert QuorumFetcher.fetch_first(sources, -1, 1_000) ==
             %{a: {:error, :cancelled}, b: {:error, :cancelled}}

    refute_receive {:invoked, _}, 100
  end