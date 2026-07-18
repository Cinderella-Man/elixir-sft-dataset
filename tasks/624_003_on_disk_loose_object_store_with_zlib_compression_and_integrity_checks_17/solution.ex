  @doc """
  Starts the object store process.

  Options:

    * `:dir` (required) — the directory in which objects are stored. It is
      created on startup if it does not already exist.
    * `:name` (optional) — a name under which to register the process.

  Returns `{:ok, pid}` on success or `{:error, reason}` on failure.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    dir = Keyword.fetch!(opts, :dir)

    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, dir, name: name)
      :error -> GenServer.start_link(__MODULE__, dir)
    end
  end