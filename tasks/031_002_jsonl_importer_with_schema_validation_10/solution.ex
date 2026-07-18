  defp check_type(value, :string, _name) when is_binary(value), do: []
  defp check_type(_value, :string, name), do: [{name, "must be a valid string"}]

  defp check_type(value, :integer, _name) when is_integer(value), do: []

  defp check_type(value, :integer, name) when is_float(value) do
    # A JSON number that is a whole number is a valid :integer — 42.0 counts;
    # only a fractional part makes it a type error.
    if value == trunc(value) * 1.0 do
      []
    else
      [{name, "must be a valid integer"}]
    end
  end

  defp check_type(_value, :integer, name), do: [{name, "must be a valid integer"}]

  defp check_type(value, :float, _name) when is_float(value), do: []
  defp check_type(value, :float, _name) when is_integer(value), do: []
  defp check_type(_value, :float, name), do: [{name, "must be a valid float"}]

  defp check_type(value, :boolean, _name) when is_boolean(value), do: []
  defp check_type(_value, :boolean, name), do: [{name, "must be a valid boolean"}]

  defp check_type(value, :list, _name) when is_list(value), do: []
  defp check_type(_value, :list, name), do: [{name, "must be a valid list"}]