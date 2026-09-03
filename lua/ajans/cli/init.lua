local Context = require("ajans.cli.context")
local Session = require("ajans.cli.session")
local State = require("ajans.cli.state")
local Util = require("ajans.util")

local M = {}

-- Undelivered prompts survive only in this slot: never logged, persisted, or
-- copied elsewhere, and replaced by the next failed delivery.
---@alias ajans.cli.RetryPhase "send"|"submit"

---@class ajans.cli.Retry
---@field msg string
---@field submit boolean
---@field phase ajans.cli.RetryPhase
---@field session_id string
---@field tool_name string

local pending_retry ---@type ajans.cli.Retry?

local RETRY_COMMAND = ":Ajans cli retry name=<tool>"
local NO_PENDING = "No undelivered prompt to retry."
local DELIVERY_FAILED = ("Delivery to the agent failed. Inspect the agent pane, resolve any sign-in, trust, or approval screen, run :checkhealth ajans, then redeliver with `%s` once resolved."):format(
  RETRY_COMMAND
)
local RETRY_REFUSED = "Refusing to retry: the %s session changed since the failed delivery; send the prompt again."
local RETRY_NOT_READY = ("Refusing to retry: %s is not ready for automated input. Resolve the pane, then run `%s` again."):format(
  "%s",
  RETRY_COMMAND
)

---@param tool_name string
---@param session table
---@param msg string
---@param submit boolean
---@param phase ajans.cli.RetryPhase
local function retain(tool_name, session, msg, submit, phase)
  pending_retry = {
    msg = msg,
    submit = submit,
    phase = phase,
    session_id = session.id,
    tool_name = tool_name,
  }
end

---@class ajans.Prompt
---@field msg string

---@class ajans.cli.Message
---@field msg? string
---@field prompt? string
---@field text? ajans.Text[]

---@class ajans.cli.Config
---@field cmd string[] Command to run the CLI tool
---@field env? table<string, string|false> Environment variables to set when running the command
---@field url? string Web URL to open when the tool is not installed
---@field keys? table<string, ajans.cli.Keymap|false>
---@field is_proc? (fun(self:ajans.cli.Tool, proc:ajans.cli.ProcessMatch):boolean)|string Regex or function to identify a running process
---@field mux_focus? boolean wether the tool needs to be focused in order to receive input
---@field mux_ready? { required?: string[], blocked?: string[] } screen markers that must gate automated input
---@field format? fun(text:ajans.Text[], str:string):string?
---@field native_scroll? boolean whether the tool handles scrolling natively

---@class ajans.cli.Show
---@field name? string
---@field focus? boolean
---@field filter? ajans.cli.Filter
---@field all? boolean

---@class ajans.cli.Hide
---@field name? string
---@field filter? ajans.cli.Filter
---@field all? boolean

---@class ajans.cli.Send: ajans.cli.Show,ajans.cli.Message
---@field submit? boolean

--- Neovim 0.11 names this supported compatibility field `buffer`; 0.12
--- metadata uses `buf` while retaining `buffer` at runtime through 0.14.
---@class ajans.keymap.set.Opts: vim.keymap.set.Opts
---@field buffer? integer

--- Keymap options similar to `vim.keymap.set` and `lazy.nvim` mappings
---@class ajans.cli.Keymap: ajans.keymap.set.Opts
---@field [1] string keymap
---@field [2] string|ajans.cli.Action
---@field mode? string|string[]

---@generic T: {name?:string, filter?:ajans.cli.Filter}
---@param opts? T|string
---@return T
local function filter_opts(opts)
  opts = type(opts) == "string" and { name = opts } or opts or {}
  ---@cast opts {name?:string, filter?:ajans.cli.Filter}
  opts.filter = opts.filter or {}
  opts.filter.name = opts.name or opts.filter.name or nil
  return opts
end

--- Select a prompt to send
---@param opts? ajans.cli.Prompt|{cb:nil}
---@overload fun(cb:fun(msg?:string))
function M.prompt(opts)
  opts = opts or {}
  opts = type(opts) == "function" and { cb = opts } or opts --[[@as ajans.cli.Prompt]]
  opts.cb = opts.cb or function(_, text)
    if text then
      M.send({ text = text })
    end
  end
  require("ajans.cli.ui.prompt").select(opts)
end

--- Start or attach to a CLI tool
---@param opts? ajans.cli.Select|{cb:nil}|{focus?:boolean}
---@overload fun(cb:fun(state?:ajans.cli.State))
function M.select(opts)
  opts = opts or {}
  opts = type(opts) == "function" and { cb = opts } or opts --[[@as ajans.cli.Select]]
  opts.filter = opts.filter or {}
  opts.cb = opts.cb
    or function(state)
      if state then
        State.attach(state, { show = true, focus = opts.focus })
      end
    end
  require("ajans.cli.ui.select").select(opts)
end

---@param opts? ajans.cli.Show
---@overload fun(name: string)
function M.show(opts)
  opts = filter_opts(opts)
  State.with(function() end, {
    all = opts.all,
    attach = true,
    filter = opts.filter,
    focus = opts.focus,
    show = true,
  })
end

---@param opts? ajans.cli.Show
---@overload fun(name: string)
function M.toggle(opts)
  opts = filter_opts(opts)
  State.with(function(state, attached)
    if not state.terminal then
      return
    end
    if not attached then
      state.terminal:toggle()
    end
    if state.terminal:is_open() and opts.focus ~= false then
      state.terminal:focus()
    end
  end, {
    attach = true,
    filter = opts.filter,
  })
end

--- Toggle focus of the terminal window if it is already open
---@param opts? ajans.cli.Show
---@overload fun(name: string)
function M.focus(opts)
  opts = filter_opts(opts)
  State.with(function(state)
    if not state.terminal then
      return
    end
    if state.terminal:is_focused() then
      state.terminal:blur()
    else
      state.terminal:focus()
    end
  end, {
    attach = true,
    filter = opts.filter,
    focus = false,
    show = true,
  })
end

---@param opts? ajans.cli.Hide
---@overload fun(name: string)
function M.hide(opts)
  opts = filter_opts(opts)
  State.with(function(state)
    return state.terminal and state.terminal:hide()
  end, {
    all = opts.all,
    filter = Util.merge(opts.filter, { terminal = true }),
  })
end

---@param opts? ajans.cli.Hide
---@overload fun(name: string)
function M.close(opts)
  opts = filter_opts(opts)
  State.with(State.detach, {
    all = opts.all,
    filter = Util.merge(opts.filter),
  })
end

-- Render a message template or prompt
---@param opts? ajans.cli.Message|string
function M.render(opts)
  return Context.get():render(opts or "")
end

--- Send a message or prompt to a CLI
---@param opts? ajans.cli.Send
---@overload fun(msg:string)
function M.send(opts)
  opts = type(opts) == "string" and { msg = opts } or opts
  opts = filter_opts(opts)

  if not opts.msg and not opts.prompt and Util.visual_mode() then
    opts.msg = "{selection}"
  end

  local msg, text = "", opts.text ---@type string?, ajans.Text[]?
  if not text then
    msg, text = M.render(opts)
    if msg == "" or not text then
      Util.warn("Nothing to send.")
      return
    elseif msg == "\n" then
      msg = "" -- allow sending a new line
      text = {}
    end
  end
  ---@cast text ajans.Text[]

  State.with(function(state)
    Util.exit_visual_mode()
    vim.schedule(function()
      local session = state.session
      if not session then
        return
      end
      session:authorize_automated_input(function(accepted)
        if not accepted or not Session.owns(session) then
          Util.warn(("Refusing to send: `%s` is no longer the active session process"):format(state.tool.name))
          return
        end
        msg = state.tool:format(text)
        if not Session.owns(session) then
          Util.warn(("Refusing to send: `%s` is no longer the active session process"):format(state.tool.name))
          return
        end
        if session:send(msg .. "\n") == false then
          retain(state.tool.name, session, msg, opts.submit == true, "send")
          Util.warn(DELIVERY_FAILED)
          return
        end
        if opts.submit and Session.owns(session) then
          if session:submit() == false then
            retain(state.tool.name, session, msg, true, "submit")
            Util.warn(DELIVERY_FAILED)
          end
        end
      end)
    end)
  end, {
    attach = true,
    filter = opts.filter,
    focus = opts.focus,
    show = true,
  })
end

--- Redeliver the most recently failed prompt. Never automatic: the user must
--- invoke it after resolving the agent pane. Refuses after the bound session
--- identity, tool, or process ownership changed.
---@param opts? {name?:string, filter?:ajans.cli.Filter}
function M.retry(opts)
  opts = filter_opts(opts)
  if not pending_retry then
    Util.warn(NO_PENDING)
    return
  end
  local pending = pending_retry
  if opts.filter.name and opts.filter.name ~= pending.tool_name then
    Util.warn(("No undelivered prompt for `%s` (pending: `%s`)"):format(opts.filter.name, pending.tool_name))
    return
  end
  State.with(function(state)
    local session = state.session
    if
      not session
      or state.tool.name ~= pending.tool_name
      or session.id ~= pending.session_id
      or not Session.owns(session)
    then
      -- The bound session is gone; redelivering to a different one could
      -- leak the prompt into an unrelated agent.
      pending_retry = nil
      Util.warn(RETRY_REFUSED:format(pending.tool_name))
      return
    end
    session:authorize_automated_input(function(accepted)
      if not accepted or not Session.owns(session) then
        Util.warn(RETRY_NOT_READY:format(state.tool.name))
        return
      end
      if pending.phase == "send" then
        if session:send(pending.msg .. "\n") == false then
          Util.warn(DELIVERY_FAILED)
          return
        end
        if pending.submit and session:submit() == false then
          retain(state.tool.name, session, pending.msg, true, "submit")
          Util.warn(DELIVERY_FAILED)
          return
        end
      elseif session:submit() == false then
        Util.warn(DELIVERY_FAILED)
        return
      end
      pending_retry = nil
      Util.info(("Redelivered the pending prompt to `%s`"):format(state.tool.name))
    end)
  end, {
    attach = true,
    filter = opts.filter,
  })
end

--- Forget any retained prompt without redelivering it
function M.clear_retry()
  pending_retry = nil
end

---@deprecated use `require("ajans.cli").prompt()`
function M.select_prompt(...)
  Util.deprecate('require("ajans.cli").select_prompt()', 'require("ajans.cli").prompt()')
  return M.prompt(...)
end

---@deprecated use `require("ajans.cli").select()`
function M.select_tool(...)
  Util.deprecate('require("ajans.cli").select_tool()', 'require("ajans.cli").select()')
  return M.select(...)
end

---@deprecated use `require("ajans.cli").send()`
function M.ask(...)
  Util.deprecate('require("ajans.cli").ask()', 'require("ajans.cli").send()')
  return M.send(...)
end

return M
