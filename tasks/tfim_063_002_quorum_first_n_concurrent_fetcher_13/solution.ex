  test "no spawned process is still alive the moment fetch_first returns" do
    parent = self()

    hang = fn name ->
      fn ->
        send(parent, {:pid, name, self()})

        receive do
          :never -> {:ok, name}
        end
      end
    end

    sources = [{:a, hang.(:a)}, {:b, hang.(:b)}, {:c, hang.(:c)}]

    result = QuorumFetcher.fetch_first(sources, 3, 100)

    assert_receive {:pid, :a, pid_a}, 1_000
    assert_receive {:pid, :b, pid_b}, 1_000
    assert_receive {:pid, :c, pid_c}, 1_000

    for pid <- [pid_a, pid_b, pid_c] do
      refute Process.alive?(pid),
             "spawned process #{inspect(pid)} outlived fetch_first"
    end

    assert result[:a] == {:error, :timeout}
    assert result[:b] == {:error, :timeout}
    assert result[:c] == {:error, :timeout}
  end