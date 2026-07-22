  def run(%__MODULE__{stages: stages}, input) do
    execute(stages, input, [])
  end