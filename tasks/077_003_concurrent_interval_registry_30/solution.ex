  @doc """
  Removes the interval previously stored under `id`.

  Returns `:ok` when the id was present, or `{:error, :not_found}` when it was
  not (or was already removed).
  """
  @spec remove(GenServer.server(), integer()) :: :ok | {:error, :not_found}
  def remove(server, id) when is_integer(id), do: GenServer.call(server, {:remove, id})