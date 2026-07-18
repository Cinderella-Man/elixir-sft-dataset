  @doc """
  Registers a service for monitoring.

  ## Options

    * `:window_size` – number of recent checks to consider (default 5).
    * `:threshold`   – failure rate (0.0–1.0) at which service is `:down` (default 0.6).

  Returns `:ok` on success, or `{:error, :already_registered}`.
  """
  @spec register(
          GenServer.server(),
          service_name(),
          (-> :ok | {:error, term()}),
          pos_integer(),
          keyword()
        ) :: :ok | {:error, :already_registered}
  def register(server, service_name, check_func, interval_ms, opts \\ []) do
    GenServer.call(server, {:register, service_name, check_func, interval_ms, opts})
  end