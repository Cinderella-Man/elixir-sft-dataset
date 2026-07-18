  @spec status(term()) :: {:ok, :healthy | :alerting} | {:error, :not_registered}
  def status(name), do: GenServer.call(__MODULE__, {:status, name})