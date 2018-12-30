import tables

type
  SciState = object
    current*: string
    documents*: TableRef[string, pointer]

var
  gSciState*: SciState

converter toPtr*(val: SomeInteger): pointer =
  return cast[pointer](val)
