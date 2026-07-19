  @spec copy_object(
          GenServer.server(),
          String.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: :ok | {:error, atom()}