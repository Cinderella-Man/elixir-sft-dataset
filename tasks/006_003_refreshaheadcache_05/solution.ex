  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    refresh_threshold = Keyword.get(opts, :refresh_threshold, 0.8)

    unless is_number(refresh_threshold) and refresh_threshold > 0.0 and
             refresh_threshold <= 1.0 do
      raise ArgumentError,
            "refresh_threshold must be in (0.0, 1.0], got: #{inspect(refresh_threshold)}"
    end

    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end