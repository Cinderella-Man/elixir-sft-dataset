  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)

    # Validate up front, in the caller's process, so bad options raise
    # ArgumentError to the caller instead of only crashing the linked child.
    _ = validate_positive(Keyword.fetch!(opts, :half_life_ms), :half_life_ms)
    _ = validate_optional_positive(Keyword.get(opts, :max_samples))

    GenServer.start_link(__MODULE__, opts, name: name)
  end