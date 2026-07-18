  @doc """
  Starts the archive server.

  `opts` is a keyword list. When it contains `:name`, the server is registered
  under that name; otherwise it is started unnamed. The module can also be used
  directly as a supervised child, e.g. `{CascadeCrud.Archive, []}`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, :ok, name: name)
      :error -> GenServer.start_link(__MODULE__, :ok)
    end
  end