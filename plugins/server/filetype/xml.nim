# xml
# Copyright Huy Doan
# Pure Nim XML parser

import strformat, strutils, strtabs


const NameIdentChars = IdentChars + {':', '-', '.'}

type
  XmlParserException* = object of Exception

  TokenKind* = enum
    TAG_BEGIN
    TAG_END
    NAME
    SIMPLE_TAG_CLOSE
    TAG_CLOSE
    STRING
    TEXT
    EQUALS
    CDATA_BEGIN
    CDATA_END

  XmlToken* = object
    kind*: TokenKind
    text*: string

  XmlNode* = ref object of RootObj
    name*: string
    text*: string
    attributes*: StringTableRef
    children*: seq[XmlNode]

template error(message: string) =
  raise newException(XmlParserException, message)


proc token(kind: TokenKind, text = ""): XmlToken =
  result.kind = kind
  result.text = text

template skip_until(c: char) =
  while(input[pos] != c):
    inc(pos)

template skip_until(s: string) =
  let length = s.len
  while(input[pos..<pos+length] != s):
    inc(pos)
  inc(pos, length)

iterator tokens*(input: string): XmlToken {.inline.} =
  ## This iterator yield tokens that extracted from `input`
  var
    pos: int
    length = input.len
    is_cdata = false
    is_text = false

  var ch = input[pos]

  while pos < length and input[pos] != '\0':
    let ch = input[pos]
    if ch in Whitespace:
      inc(pos)
      continue
    case ch
    of '<':
      if not is_cdata:
        inc(pos)
        case input[pos]:
        of '?':
          # skips prologue
          skip_until('>')
          # print out prologue
          #echo input[0..pos]
          inc(pos)
        of '!':
          inc(pos)
          if input[pos..pos+6] == "[CDATA[":
            # CDATA
            is_cdata = true
            is_text = true
            yield token(CDATA_BEGIN)
            inc(pos, 6)
          elif input[pos..pos+1] == "--":
            # skips comment
            let comment_start = pos-2
            skip_until("-->")
            # print out full of comment
            #echo input[comment_start..<pos]
          else:
            error(fmt"text expected, found ""{input[pos]}"" at {pos}")
        of '/':
          yield token(TAG_CLOSE)
          is_text = false
        else:
          dec(pos)
          yield token(TAG_BEGIN)
          is_text = false
        inc(pos)
    of ']':
      if input[pos..pos+2] != "]]>":
        error(fmt"cdata end ""]]>"" expected, found {input[pos..pos+2]} at {pos}")
      is_text =  true
      is_cdata = false
      yield token(CDATA_END)
      inc(pos, 3)
    of '\'', '"':
      inc(pos)
      var next_ch = input.find(ch, pos)
      if next_ch == -1:
        error(fmt"unable to find matching string quote last found {pos}") 
      yield token(STRING, input[pos..<next_ch])
      pos = next_ch+1
    of '>':
      inc(pos)
      is_text = true
      yield token(TAG_END)
    of '=':
      inc(pos)
      yield token(EQUALS)
    of '/':
      if input[pos+1] == '>':
        yield token(SIMPLE_TAG_CLOSE)
        inc(pos, 2)
    else:
      if(is_text):
        var text_end = 0
        if is_cdata:
          text_end = input.find("]]>", pos)
        else:
          text_end = input.find('<', pos)
        if text_end == -1:
          error(fmt"unable to find ending point of text, started at {pos}")
        yield token(TEXT, input[pos..<text_end])
        pos = text_end
        is_text = false
      else:
        var
          name = ""
          name_start = pos
        var c = input[pos]
        if c in IdentStartChars:
          while c in NameIdentChars:
            name.add(c)
            inc(pos)
            c = input[pos]
          yield token(NAME, name)
          if not (c in NameIdentChars):
            dec(pos)
        inc(pos)

proc tokens*(input: string): seq[XmlToken] =
  result = @[]
  for token in input.tokens:
    result.add(token)


proc newNode(name: string, text = ""): XmlNode =
  ## create new node
  new(result)
  result.name = name
  result.text = text

proc child*(node: XmlNode, name: string): XmlNode =
  ## finds the first element of `node` with name `name`
  ## returns `nil` on failure
  if node.children.len != 0:
    for n in node.children:
      if n.name == name:
        result = n
        break

proc `$`*(node: XmlNode): string =
  result = "<"
  result.add(node.name)
  if not node.attributes.isNil:
    for k, v in node.attributes.pairs:
      result.add(fmt" {k}=""{v}""")
  if node.text.len == 0 and node.children.len == 0:
    result.add(" />")
    return
  elif node.text.len > 0:
    result.add(">" & node.text)
  else:
    result.add(">")

  if node.children.len != 0:
    for child in node.children:
      result.add($child)
  result.add("</" & node.name & ">")


proc addChild*(node, child: XmlNode) =
  if node.children.len == 0:
    node.children = @[]
  node.children.add(child)

proc hasAttr*(node: XmlNode, name: string): bool =
  ## returns `true` if `node` has attribute `name`
  if node.attributes.isNil:
    result = false
  else:
    result = node.attributes.hasKey(name)

proc attr*(node: XmlNode, name: string): string =
  ## returns value of attribute `name`, returns "" on failure
  if not node.attributes.isNil:
    result = node.attributes.getOrDefault(name)

proc setAttr(node: XmlNode, name, value: string) =
  if node.attributes.isNil:
    node.attributes = newStringTable(modeCaseInsensitive)
  node.attributes[name] = value

proc parseNode(tokens: seq[XmlToken], start = 0): (XmlNode, int) =
  var
    node: XmlNode
    attrName: string
  var i = start

  assert tokens[start].kind == TAG_BEGIN

  while i < tokens.len:
    let t = tokens[i]
    case t.kind
    of TAG_BEGIN:
      if not node.isNil:
        let (n, j) = parseNode(tokens, i)
        node.addChild(n)
        i = j
    of NAME:
      if tokens[i-1].kind == TAG_BEGIN:
        node = newNode(t.text)
      else:
        attrName = t.text
    of STRING:
      if tokens[i-1].kind == EQUALS:
        node.setAttr(attrName, t.text)
    of TEXT:
      node.text = t.text
    of SIMPLE_TAG_CLOSE:
      return (node, i)
    of TAG_CLOSE:
      assert tokens[i+1].text == node.name
      return (node, i)
    else:
      discard
    inc(i)

proc parseXml*(input: string): XmlNode =
  ## this proc takes an XML `input` as string
  ## returns root XmlNode
  var tokens = tokens(input)
  #var (result, _) = parseNode(tokens, 0)
  let (root, _) = parseNode(tokens)
  result = root


when isMainModule:
  let xml = """<?xml version="1.0" encoding="UTF-8"?>
<!-- example -->
<classes>
    <simple closed="true"/>
    <note><![CDATA[This text is CDATA<>]]></note>
    <class name="Klient">
        <attr type="int">id</attr>
        <attr type="String">imie</attr>
        <attr type="String">nazwisko</attr>
        <attr type="Date">dataUr</attr>
    </class>
    <class name="Wizyta">
        <attr type="int">id</attr>
        <attr type="Klient">klient</attr>
        <attr type="Date">data</attr>
    </class>
</classes>
"""
  assert tokens(xml).len == 109
  #for t in xml.tokens:
  #  echo t
  var root = parseXml(xml)
  assert root.name == "classes"
  let
    simple = root.children[0]
    note = root.children[1]
    class1 = root.children[2]
    class2 = root.children[3]

  assert simple.name == "simple"
  assert simple.hasAttr("closed")
  assert simple.attr("closed") == "true"
  assert simple.text == ""

  assert note.name == "note"
  assert note.text == "This text is CDATA<>"

  assert class1.hasAttr("name")
  assert class1.children.len == 4

  assert class1.children[3].hasAttr("type")
  assert class1.children[3].attr("type") == "Date"




