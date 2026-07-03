  def start_link(opts) do
    capacity = Keyword.fetch!(opts, :capacity)

    unless is_integer(capacity) and capacity > 0 do
      raise ArgumentError, ":capacity must be a positive integer, got: #{inspect(capacity)}"
    end

    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end