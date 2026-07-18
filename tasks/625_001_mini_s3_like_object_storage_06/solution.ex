  @impl true
  def init(root_dir) do
    root_dir = Path.expand(root_dir)
    buckets_dir = Path.join(root_dir, "buckets")
    File.mkdir_p!(buckets_dir)

    state = %{
      root_dir: root_dir,
      buckets_dir: buckets_dir,
      # multipart uploads are ephemeral (in-memory only)
      # %{upload_id => %{bucket, key, content_type, metadata, parts}}
      multipart_uploads: %{}
    }

    {:ok, state}
  end