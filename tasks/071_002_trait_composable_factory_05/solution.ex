  @doc "Starts the named Agent backing all sequence counters."
  @spec start() :: {:ok, pid()} | {:error, term()}
  def start do
    Agent.start_link(fn -> %{} end, name: @agent)
  end