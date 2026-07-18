  @doc """
  Returns `%{left: [records], right: [records]}` — records awaiting a counterpart.

  Order within each list is unspecified. Does not change state.
  """
  @spec pending(GenServer.server()) :: %{left: [stream_record()], right: [stream_record()]}
  def pending(server) do
    GenServer.call(server, :pending)
  end