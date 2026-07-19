  @spec search(GenServer.server(), String.t(), keyword()) ::
          [%{id: String.t(), score: number()}]