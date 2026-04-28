type
  BenchScale* = object
    name*: string
    columns*: int
    rows*: int

const
  BenchScales* = [
    BenchScale(name: "small", columns: 20, rows: 15),
    BenchScale(name: "medium", columns: 30, rows: 20),
    BenchScale(name: "large", columns: 40, rows: 30),
    BenchScale(name: "xlarge", columns: 50, rows: 40),
    BenchScale(name: "xxlarge", columns: 60, rows: 50)
  ]

proc findBenchScale*(name: string): BenchScale =
  for scale in BenchScales:
    if scale.name == name:
      return scale
  raise newException(ValueError, "unknown benchmark scale: " & name)
