-- 任意改ページフィルター
--
-- Markdown原稿中の次のfenced Divを、出力形式ごとの改ページへ変換する。
-- 前後は空行で区切る。
--
-- ::: pagebreak
--
-- :::
--
-- PDF  : \clearpage
-- DOCX : OpenXMLのページ区切り
-- EPUB : CSSのbreak-before / page-break-before

local function is_pagebreak(div)
  if div.identifier == "pagebreak" then
    return true
  end

  for _, class in ipairs(div.classes) do
    if class == "pagebreak" then
      return true
    end
  end

  return false
end

function Div(div)
  if not is_pagebreak(div) then
    return nil
  end

  if FORMAT:match("latex") then
    return pandoc.RawBlock("latex", "\\clearpage")
  end

  if FORMAT:match("docx") then
    local openxml = [[
<w:p>
  <w:r>
    <w:br w:type="page"/>
  </w:r>
</w:p>
]]
    return pandoc.RawBlock("openxml", openxml)
  end

  if FORMAT:match("epub") then
    local html = [[
<div style="break-before: page; page-break-before: always;">&#160;</div>
]]
    return pandoc.RawBlock("html", html)
  end

  return {}
end
