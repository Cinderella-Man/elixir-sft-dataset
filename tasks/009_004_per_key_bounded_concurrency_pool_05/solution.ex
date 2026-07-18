  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    max_concurrency = Keyword.fetch!(opts, :max_concurrency)

    if not is_integer(max_concurrency) or max_concurrency < 1 do
      raise ArgumentError,
            ":max_concurrency must be a positive integer, got: #{inspect(max_concurrency)}"
    end

    server_opts = Keyword.take(opts, [:name])
    GenServer.start_link(__MODULE__, %{max_concurrency: max_concurrency}, server_opts)
  end