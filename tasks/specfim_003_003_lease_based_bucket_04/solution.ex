  @spec release(GenServer.server(), term(), reference(), :completed | :cancelled) ::
          :ok | {:error, :unknown_lease}