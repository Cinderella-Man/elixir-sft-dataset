  @doc "Executes the saga from the beginning."
  @spec execute(t(), context()) :: run_result()
  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    run(steps, [], context, [])
  end