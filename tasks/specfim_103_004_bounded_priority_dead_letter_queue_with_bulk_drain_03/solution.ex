  @spec push(GenServer.server(), term(), term(), term(), map(), :high | :normal | :low) ::
          {:ok, term()} | {:error, :full}