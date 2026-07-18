  @impl GenServer
  def init(_opts) do
    # :set          — one entry per key (duplicate keys overwrite)
    # :named_table  — accessible by name from any process
    # :public       — any process may read and write without going through the owner
    # read_concurrency / write_concurrency — kernel-level optimisations for
    #   the mixed read-heavy / write-heavy workloads typical of metrics
    :ets.new(@table, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{}}
  end