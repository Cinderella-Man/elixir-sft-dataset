  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {script, opts} = Keyword.pop(opts, :script, [@default_initial])
    {policy, opts} = Keyword.pop(opts, :on_exhaust, :repeat_last)
    {name_opt, _rest} = Keyword.pop(opts, :name)
    gen_opts = if name_opt, do: [name: name_opt], else: []
    GenServer.start_link(__MODULE__, {script, policy}, gen_opts)
  end