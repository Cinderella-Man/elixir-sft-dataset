def value(max_depth) when is_integer(max_depth) and max_depth <= 0 do
  scalar()
end

def value(max_depth) when is_integer(max_depth) and max_depth > 0 do
  child = value(max_depth - 1)

  SD.one_of([
    scalar(),
    array(child, 5),
    object(child, 5)
  ])
end