  @doc """
  Starts the `CacheLayer` GenServer and links it to the calling process.

  ## Options

  Accepts any option understood by `GenServer.start_link/3`. In practice the
  most useful one is:

    * `:name` – registers the process under the given name so callers can
      reference it by atom instead of by pid.

  ## Examples

      {:ok, pid} = CacheLayer.start_link()
      {:ok, _}   = CacheLayer.start_link(name: :my_cache)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end