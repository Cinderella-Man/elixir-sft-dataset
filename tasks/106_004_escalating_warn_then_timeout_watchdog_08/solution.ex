  @spec phase(term()) :: {:ok, :healthy | :warned} | {:error, :not_registered}
  def phase(name), do: GenServer.call(__MODULE__, {:phase, name})