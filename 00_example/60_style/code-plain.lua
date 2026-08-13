-- markdown/textコードフェンスを単色表示にする。
--
-- markdownとtextは説明用コードとして使うことが多いため、
-- Pandocのシンタックスハイライト対象から外す。
-- powershell、python、jsonなどの言語指定は従来どおり保持する。

function CodeBlock(block)
  local make_plain = false
  local classes = pandoc.List()

  for _, class in ipairs(block.classes) do
    if class == "markdown" or class == "text" then
      make_plain = true
    else
      classes:insert(class)
    end
  end

  if make_plain then
    block.classes = classes
  end

  return block
end
