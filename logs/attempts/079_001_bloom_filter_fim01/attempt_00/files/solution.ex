defp optimal_m(n, p) do
  ceil(-n * :math.log(p) / (@ln2 * @ln2))
end