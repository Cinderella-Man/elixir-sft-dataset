  @doc """
  Appends `value` to the named stream.  Creates the stream on first use.
  Always returns `:ok`.
  """
  @spec push(GenServer.server(), term(), number()) :: :ok
  def push(server, name, value) do
    GenServer.call(server, {:push, name, value})
  end