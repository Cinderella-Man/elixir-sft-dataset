  def add(server, element) do
    case GenServer.call(server, {:add, element}) do
      :ok ->
        :ok

      {:error, :tombstoned} ->
        raise ArgumentError,
              "cannot re-add element #{inspect(element)}: it has been permanently removed from the 2P-Set"
    end
  end