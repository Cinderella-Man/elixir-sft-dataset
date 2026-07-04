  defp generate_fake(value, seed) do
    <<b0, b1, b2, b3, b4, b5, b6, _rest::binary>> =
      :crypto.hash(:sha256, "#{inspect(seed)}:#{value}")

    first = Enum.at(@first_names, rem(b0, length(@first_names)))
    last = Enum.at(@last_names, rem(b1, length(@last_names)))

    case rem(b2, 4) do
      0 ->
        "#{first} #{last}"

      1 ->
        domain = Enum.at(@domains, rem(b3, length(@domains)))
        "#{String.downcase(first)}.#{String.downcase(last)}@#{domain}"

      2 ->
        suffix = rem(b3 * 256 + b4, 9000) + 1000
        "#{first}#{suffix}"

      3 ->
        suffix = rem(b5 * 256 + b6, 90) + 10
        "#{String.downcase(first)}-#{String.downcase(last)}-#{suffix}"
    end
  end