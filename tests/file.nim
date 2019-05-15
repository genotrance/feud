let
  newDoc = "tests\\newdoc.txt"

discard @[
  "newDoc",
  "eMsg SCI_APPENDTEXT 10 HelloWorld",
  "saveAs " & newDoc,
  "close"
].execFeudC()

doAssert newDoc.fileExists() == true, "Failed newDoc"
newDoc.rmFile()

doAssert @[
  "open -r *.xml",
  "closeAll"
].execFeudC().contains("langs.model.xml"), "Failed recursive open"