  defp parse_q(params) do
    Enum.find_value(params, 1.0, fn p ->
      case String.split(p, "=") do
        ["q", val] ->
          case Float.parse(val) do
            {f, _} -> f
            :error -> 1.0
          end

        _ ->
          nil
      end
    end)
  end