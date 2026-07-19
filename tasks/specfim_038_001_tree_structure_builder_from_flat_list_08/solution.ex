  @spec dfs(id(), %{id() => [id()]}, map(), [id()]) ::
          {:ok, map()} | {:error, {:cycle_detected, [id()]}}