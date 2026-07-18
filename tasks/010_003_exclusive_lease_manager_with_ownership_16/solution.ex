  @doc """
  Releases a lease on `resource`. Only the current owner may release it.

  Returns `:ok` on success, or `{:error, :not_held}` if the lease doesn't
  exist, has expired, or is held by a different owner.
  """
  @spec release(server(), resource(), owner()) :: :ok | {:error, :not_held}
  def release(server, resource, owner) do
    GenServer.call(server, {:release, resource, owner})
  end