  @impl true
  def init(opts) do
    root = Keyword.get(opts, :root_dir, @default_root)
    File.mkdir_p!(root)
    {:ok, %{root_dir: root, buckets: load_buckets(root)}}
  end