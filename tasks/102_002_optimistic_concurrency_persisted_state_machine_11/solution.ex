  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(opts) do
    repo = Keyword.fetch!(opts, :repo)
    {:ok, %{repo: repo, entities: %{}}}
  end