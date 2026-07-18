  # The decoded payload is untrusted: its value must have the exact type the
  # sort field produces, otherwise Erlang's cross-type term ordering would
  # silently slice the page instead of failing loudly.
  defp valid_key?("name", value, id), do: is_binary(value) and is_integer(id)
  defp valid_key?("price", value, id), do: is_integer(value) and is_integer(id)
  defp valid_key?("id", value, id), do: is_integer(value) and is_integer(id) and value == id
  defp valid_key?(_, _, _), do: false