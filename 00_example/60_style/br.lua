function RawInline(el)
  local text = el.text:lower()

  if el.format == "html" and text:match("^<br%s*/?%s*>$") then
    return pandoc.LineBreak()
  end

  return el
end
