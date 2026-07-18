  @impl GenServer
  def init(micros) when is_integer(micros), do: {:ok, micros}