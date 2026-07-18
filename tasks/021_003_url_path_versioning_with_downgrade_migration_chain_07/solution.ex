  defp downgrade(doc, target) do
    target
    |> steps_to()
    |> Enum.reduce(doc, &apply_step/2)
  end