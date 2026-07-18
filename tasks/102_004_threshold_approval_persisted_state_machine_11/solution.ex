  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(opts) do
    repo = Keyword.fetch!(opts, :repo)
    required = Keyword.get(opts, :required_approvals, @default_required_approvals)

    {:ok, %{repo: repo, required: required, entities: %{}}}
  end