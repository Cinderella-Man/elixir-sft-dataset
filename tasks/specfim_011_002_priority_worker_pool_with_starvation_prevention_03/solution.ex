  @spec submit(GenServer.server(), (-> any()), :high | :normal | :low) ::
          {:ok, reference()} | {:error, :queue_full}