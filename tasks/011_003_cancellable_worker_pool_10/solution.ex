  @impl true
  def init(opts) do
    pool_size = Keyword.get(opts, :pool_size, 3)
    max_queue = Keyword.get(opts, :max_queue, 10)

    {:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

    state = %State{
      sup: sup,
      pool_size: pool_size,
      max_queue: max_queue
    }

    new_state =
      Enum.reduce(1..pool_size, state, fn _, acc ->
        {:ok, pid} = start_worker(acc.sup)
        mref = Process.monitor(pid)

        %{
          acc
          | idle_workers: [pid | acc.idle_workers],
            monitors: Map.put(acc.monitors, mref, pid)
        }
      end)

    {:ok, new_state}
  end