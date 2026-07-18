  @impl true
  def init(opts) do
    quota = Keyword.get(opts, :quota_bytes, 10_000_000)
    {:ok, %{quota: quota, files: %{}, usage: %{}}}
  end