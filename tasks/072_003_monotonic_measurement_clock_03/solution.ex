def measure(clock, fun) when is_function(fun, 0) do
  t0 = monotonic(clock, :microsecond)
  result = fun.()
  t1 = monotonic(clock, :microsecond)
  {result, div(t1 - t0, 1000)}
end