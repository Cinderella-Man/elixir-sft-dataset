  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    forward(steps, context, [])
  end