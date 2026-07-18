  @doc "Stores an object in the given bucket under the given key."
  @spec put_object(
          GenServer.server(),
          String.t(),
          String.t(),
          binary(),
          String.t(),
          map()
        ) :: :ok | {:error, atom()}
  def put_object(
        server,
        bucket,
        key,
        data,
        content_type \\ "application/octet-stream",
        metadata \\ %{}
      ) do
    GenServer.call(server, {:put_object, bucket, key, data, content_type, metadata})
  end