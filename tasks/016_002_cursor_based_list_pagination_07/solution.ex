  defp parse_direction(%{"direction" => "prev"}), do: :prev
  defp parse_direction(_), do: :next