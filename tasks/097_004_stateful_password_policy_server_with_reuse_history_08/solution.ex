  def init(opts) do
    opts_map = Map.new(opts)

    state = %{
      history_size: Map.get(opts_map, :history_size, @default_history_size),
      policy: build_policy(opts_map),
      users: %{}
    }

    {:ok, state}
  end