  @spec submit(GenServer.server(), (-> any()), keyword()) ::
          {:ok, reference()} | {:error, :queue_full}