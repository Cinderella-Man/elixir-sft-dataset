  @impl GenServer
  def init(opts) do
    buckets = Keyword.get(opts, :buckets, @default_buckets)
    :persistent_term.put({@table, :buckets}, buckets)

    :ets.new(@table, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{buckets: buckets}}
  end