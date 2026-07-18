  @doc "Executes the saga against an initial context map."
  @spec execute(t(), context()) :: {:ok, context()} | failure()
  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    run(steps, [], context)
  end