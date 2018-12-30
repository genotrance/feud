import tables

type
  SciState = object
    current*: string
    documents*: TableRef[string, pointer]
    plugins*: TableRef[string, ptr Channel[seq[string]]]

var
  gSciState*: SciState

converter toPtr*(val: SomeInteger): pointer =
  return cast[pointer](val)
