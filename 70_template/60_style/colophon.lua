-- PDF用の奥付配置フィルター
--
-- class="colophon"のDivを検出し、LaTeX出力時だけ
-- 独立ページの下側へ配置する。
-- EPUBとDOCXでは内容を変更しない。

local function has_class(div, class_name)
  for _, class in ipairs(div.classes) do
    if class == class_name then
      return true
    end
  end

  return false
end

local function blocks_to_latex(blocks)
  local document = pandoc.Pandoc(blocks)

  return pandoc.write(
    document,
    "latex"
  )
end

function Div(div)
  if not has_class(div, "colophon") then
    return nil
  end

  if not FORMAT:match("latex") then
    return nil
  end

  local content = blocks_to_latex(div.content)

  local latex = table.concat({
    "\\clearpage",
    "\\thispagestyle{empty}",
    "\\vspace*{\\fill}",
    "",
    "\\begin{minipage}{\\textwidth}",
    content,
    "\\end{minipage}",
    "",
    "\\vspace*{10mm}"
  }, "\n")

  return pandoc.RawBlock("latex", latex)
end
