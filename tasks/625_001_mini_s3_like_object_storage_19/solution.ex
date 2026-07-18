  @doc "Initiates a multipart upload, returning an upload ID."
  @spec start_multipart(
          GenServer.server(),
          String.t(),
          String.t(),
          String.t(),
          map()
        ) :: {:ok, String.t()} | {:error, atom()}
  def start_multipart(
        server,
        bucket,
        key,
        content_type \\ "application/octet-stream",
        metadata \\ %{}
      ) do
    GenServer.call(server, {:start_multipart, bucket, key, content_type, metadata})
  end