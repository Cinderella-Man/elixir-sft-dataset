  @doc "Runs the saga from `context`."
  @spec execute(t(), context()) :: {:ok, context()} | {:error, error()}
  def execute(%__MODULE__{stages: stages}, context) when is_map(context) do
    run_stages(stages, 0, context, [])
  end