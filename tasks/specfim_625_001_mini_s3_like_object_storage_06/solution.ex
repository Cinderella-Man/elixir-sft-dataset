  @spec put_object(
          GenServer.server(),
          String.t(),
          String.t(),
          binary(),
          String.t(),
          map()
        ) :: :ok | {:error, atom()}