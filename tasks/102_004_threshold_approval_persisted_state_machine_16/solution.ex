  @doc """
  Start the state-machine server.

  Options:

    * `:repo` (required) — a configured Ecto repo module used for all
      persistence.
    * `:required_approvals` — a positive integer number of approvals
      needed to reach `:approved`. Defaults to `2`.
    * `:name` — optional process name for registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end