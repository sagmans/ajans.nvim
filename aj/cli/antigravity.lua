---@type ajans.cli.Config
return {
  cmd = { "agy" },
  -- Agy eats typed input until its own UI settles: sign-in restoration and
  -- folder-trust screens accept no prompt. Hold automated input until the
  -- stable input footer appears; the trust screen must stay user-owned.
  mux_ready = {
    required = { "? for shortcuts" },
    blocked = { "Do you trust the contents of this project" },
  },
  is_proc = "\\<agy\\>",
  url = "https://antigravity.google",
  format = function(text)
    local Text = require("ajans.text")
    Text.transform(text, function(str)
      return str:gsub("([^%w/_%.%-])", "\\%1")
    end, "AjansLocFile")
    return Text.to_string(text)
  end,
}
