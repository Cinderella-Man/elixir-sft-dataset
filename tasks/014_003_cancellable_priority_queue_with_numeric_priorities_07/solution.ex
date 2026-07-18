  @spec cancel(server(), reference()) :: :ok | {:error, :not_found}
  def cancel(server, ref) when is_reference(ref) do
    GenServer.call(server, {:cancel, ref})
  end