  @impl true
  def init(rules) do
    {:ok, %{rules: rules, maps: %{}, counters: %{}}}
  end