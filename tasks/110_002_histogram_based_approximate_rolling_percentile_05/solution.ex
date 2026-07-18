  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)

    # Validate eagerly in the caller process. If we let `init/1` raise instead,
    # the freshly-spawned (and linked) GenServer would exit with a non-normal
    # reason and take the caller down with it, rather than surfacing a clean
    # ArgumentError.
    _ = validate_edges(Keyword.get(opts, :edges))
    _ = validate_positive(Keyword.fetch!(opts, :window_ms), :window_ms)
    _ = validate_positive(Keyword.get(opts, :slots, 60), :slots)

    GenServer.start_link(__MODULE__, opts, name: name)
  end