  @spec expired(server()) :: [{term(), priority()}]
  def expired(server) do
    GenServer.call(server, :expired)
  end