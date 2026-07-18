  @doc """
  Indexes `id` with the given `fields` map (`field_name => text`).

  Re-indexing an existing `id` cleanly replaces the previous version.
  Returns `:ok`.
  """
  @spec index(GenServer.server(), String.t(), %{optional(any()) => String.t()}) :: :ok
  def index(server, id, fields) do
    GenServer.call(server, {:index, id, fields})
  end