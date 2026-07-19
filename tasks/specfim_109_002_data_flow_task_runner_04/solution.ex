  @spec run_all(GenServer.server()) ::
          {:ok, map()}
          | {:error, {:cycle, [term()]}}
          | {:error, {:unknown_dependencies, [term()]}}