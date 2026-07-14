# Changelog

## Unreleased

### ⚠ BREAKING CHANGES

* **cli:** replace legacy multiplexer options with `cli.mux.backend = "auto" | "tmux" | "herdr"`; `cli.mux.enabled` is removed and ignored, with no backend-disable value. Remove Ajans CLI mappings and avoid its CLI commands when session integration is not wanted. `auto` may select a running Herdr server instead of tmux
* **cli:** preserve tmux scrollback and split settings while enforcing Herdr's 1-1000 line and 0.1-0.9 layout limits in its adapter
* **cli:** replace bundled `gemini` tool with `antigravity` (`agy` binary). Rename `cli.tools.gemini` to `cli.tools.antigravity` in your config; install the [Antigravity CLI](https://antigravity.google) instead of Gemini CLI. Existing sessions keyed to `gemini` will not attach as `antigravity`.

### Features

* **cli:** add full Herdr `>= 0.7.0` session backend support on macOS and Linux, including discovery, persistent attachment, native tabs/splits, input, scrollback, health checks, and automatic backend selection

## [2.3.0](https://github.com/assagman/ajans.nvim/compare/v2.2.0...v2.3.0) (2026-03-20)


### Features

* **config:** ctrl+x now blurs instead of another hide ([122c1ca](https://github.com/assagman/ajans.nvim/commit/122c1ca62fa27b4c2213879bbb04d890a16468ce))


### Bug Fixes

* **cli:** incorrect range when on same row. Closes [#186](https://github.com/assagman/ajans.nvim/issues/186). Fixes [#184](https://github.com/assagman/ajans.nvim/issues/184) ([ff8ef47](https://github.com/assagman/ajans.nvim/commit/ff8ef479ff6b2f560cfbca0d8b4b8b4593969ab0))
* **docs:** update Claude installation instructions ([#255](https://github.com/assagman/ajans.nvim/issues/255)) ([43c7a11](https://github.com/assagman/ajans.nvim/commit/43c7a11b397afc7cc3c14113a52811a0d32ef6bf))

## [2.2.0](https://github.com/assagman/ajans.nvim/compare/v2.1.0...v2.2.0) (2026-03-20)


### Features

* **agents:** add pi agent ([#247](https://github.com/assagman/ajans.nvim/issues/247)) ([7e9da9b](https://github.com/assagman/ajans.nvim/commit/7e9da9b12a5da46c6abd57ebf650e9d32c483ce7))
* **terminal:** add files/buffers inline with spaces from picker. Closes [#133](https://github.com/assagman/ajans.nvim/issues/133) ([e743ac7](https://github.com/assagman/ajans.nvim/commit/e743ac74b90826d0b3a33f44c9906baa306e46b9))
* **terminal:** make re-entering terminal/normal mode more sensible ([9eb6530](https://github.com/assagman/ajans.nvim/commit/9eb653079f9055fe62ff63e918c36c7c4c92e0a9))


### Bug Fixes

* **codex:** update deprecated search option ([#166](https://github.com/assagman/ajans.nvim/issues/166)) ([88cb6dd](https://github.com/assagman/ajans.nvim/commit/88cb6dd487ddf35134987654eec91e20fddc1e54))
* **config:** remove web search option from codex command ([#257](https://github.com/assagman/ajans.nvim/issues/257)) ([f8b4f58](https://github.com/assagman/ajans.nvim/commit/f8b4f58c3b8b2cf8ddffa8d6c23b95c9010ae158))
* **config:** update codex search option ([#167](https://github.com/assagman/ajans.nvim/issues/167)) ([c302dba](https://github.com/assagman/ajans.nvim/commit/c302dbaf0fcbde909838b296719bbf84e3db6e20))
* **opencode:** Use alt+p instead of ctrl+p. Fixes [#175](https://github.com/assagman/ajans.nvim/issues/175) ([a6fe80f](https://github.com/assagman/ajans.nvim/commit/a6fe80fc9d0a1db2bb7a55e8f313ed9e17282e3e))
* **terminal:** ready check should not fail if cli window is closed. Fixes [#252](https://github.com/assagman/ajans.nvim/issues/252) ([6b69c42](https://github.com/assagman/ajans.nvim/commit/6b69c42031950164b208b1abf78018ab4a86cdec))
* **treesitter:** dont use treesitter stringbuffers ([317ada1](https://github.com/assagman/ajans.nvim/commit/317ada137f2b34cccc872b68f0a29d987cbce438))

## [2.1.0](https://github.com/assagman/ajans.nvim/compare/v2.0.0...v2.1.0) (2025-10-23)


### Features

* **cli:** added snacks picker action to send files with ajans. Closes [#134](https://github.com/assagman/ajans.nvim/issues/134) ([96b84ff](https://github.com/assagman/ajans.nvim/commit/96b84ff4fca047dd561219e92060c5a16d4a6e20))
* **cli:** added snacks/telescope/fzf-lua pickers for selecting files/buffers to send ([0da0e16](https://github.com/assagman/ajans.nvim/commit/0da0e16089d62b882d2a7b2d8c9809a6185bf644))
* **cli:** added terminal keymaps `<c-f>` to select files and `<c-b>` to select buffers to send. ([c827ad2](https://github.com/assagman/ajans.nvim/commit/c827ad2826bd7fe444cddae8474e0bfe05ad3d93))
* **diagnostics:** diagnostics will now use the visual selection if needed. Closes [#146](https://github.com/assagman/ajans.nvim/issues/146) ([fb0cbaa](https://github.com/assagman/ajans.nvim/commit/fb0cbaa700006edc3318a026a14adb03f41d99a5))
* **snacks:** make `vim.ui.select` snacks options configurable. Closes [#149](https://github.com/assagman/ajans.nvim/issues/149) ([7568825](https://github.com/assagman/ajans.nvim/commit/756882545e4fcb50185e3089ee77a67706951139))
* **status:** added cli status to be used in statuslines. Closes [#143](https://github.com/assagman/ajans.nvim/issues/143) ([e291b6b](https://github.com/assagman/ajans.nvim/commit/e291b6b3cc66abf04c120e50a502e18323dfedd2))
* **terminal:** smarter way to determine that the cli tool is ready to accept input. Closes [#150](https://github.com/assagman/ajans.nvim/issues/150) ([04265f7](https://github.com/assagman/ajans.nvim/commit/04265f7c1419bfcbb3b98b6d99bd3f5bd9cebd9b))


### Bug Fixes

* **cli.loc:** allow row/col to be `nil` ([bb87f41](https://github.com/assagman/ajans.nvim/commit/bb87f419dd56a7fabe0de017e18ace243a2d7aee))
* **cli.picker:** do the stop/start insert dance to keep pickers / terminals happy ([9941a1c](https://github.com/assagman/ajans.nvim/commit/9941a1cf4eb7ca1cb9c155207a4249ff45e6123d))
* **cli.status:** schedule detach event to prevent loop. Closes [#144](https://github.com/assagman/ajans.nvim/issues/144) ([9390cb7](https://github.com/assagman/ajans.nvim/commit/9390cb72de62e6ae27dbd98dfda32059662290f1))
* **cli:** use filter options for send. Closes [#138](https://github.com/assagman/ajans.nvim/issues/138) ([d0ee1ef](https://github.com/assagman/ajans.nvim/commit/d0ee1ef6a8257d8b66be66a5797ae6451385ea0b))
* **opencode:** opencode implements scrolling natively, so don't use scrollback there. See [#152](https://github.com/assagman/ajans.nvim/issues/152) ([d9e1fa2](https://github.com/assagman/ajans.nvim/commit/d9e1fa2124340d3337d1a3a22b2f20de0701affe))
* **scrollback:** focus issues with other terminals entering/leaving like fzf-lua ([ff55eb3](https://github.com/assagman/ajans.nvim/commit/ff55eb3015d2b4250886d09bea777219179ab61b))
* **terminal:** better tracking of terminal mode when entering/leaving the ajans window ([22a6326](https://github.com/assagman/ajans.nvim/commit/22a632665774961a8039eb5f5ff02835728f26d2))
* **terminal:** enbable/disable cursorline when in normal/terminal mode in the ajans window ([83b6815](https://github.com/assagman/ajans.nvim/commit/83b6815c0ed738576f101aad31c79b885c892e0f))
* **terminal:** fckup with scrollback ([cbbf53b](https://github.com/assagman/ajans.nvim/commit/cbbf53b7ecad1cdf3a3daa5a22506b9349696e45))
* **terminal:** handle closing the last window. Closes [#124](https://github.com/assagman/ajans.nvim/issues/124) ([99824c2](https://github.com/assagman/ajans.nvim/commit/99824c2b63d547a1fd90e24fa9e8fb648382645d))
* **terminal:** increase initial send delay when opening the terminal. Closes [#150](https://github.com/assagman/ajans.nvim/issues/150) ([e98008f](https://github.com/assagman/ajans.nvim/commit/e98008f9dcb504b745e465169196e1e1b26028da))
* **terminal:** only use scrollback buffer when needed ([9d9d8cc](https://github.com/assagman/ajans.nvim/commit/9d9d8cca622d12d81c58cd10b51a428e2fc2cdd7))

## [2.0.0](https://github.com/assagman/ajans.nvim/compare/v1.3.0...v2.0.0) (2025-10-17)


### ⚠ BREAKING CHANGES

* **config:** changed the default keymaps. Please check the updated documentation and example mappings

### Features

* **cli.claude:** transform line ranges to a format Claude can understand. Closes [#59](https://github.com/assagman/ajans.nvim/issues/59) ([4a492da](https://github.com/assagman/ajans.nvim/commit/4a492da6e863d06b15e887be97dd43c50b76f11d))
* **cli.select:** better distinction between attaching to terminal/external ([48d0bf6](https://github.com/assagman/ajans.nvim/commit/48d0bf66459f2fab8d917fea961bbe95c5d829c1))
* **cli:** `close()` on an external session, now detaches from that session. Closes [#98](https://github.com/assagman/ajans.nvim/issues/98) ([d2e6c64](https://github.com/assagman/ajans.nvim/commit/d2e6c6447e750a5f565ae1a832f1ca7fd8e6e8dd))
* **cli:** added `<c-q>` to hide in normal mode, so from terminal double `<c-q>` will hide ([358804c](https://github.com/assagman/ajans.nvim/commit/358804c71cd988b1ce7efc7a91e3d265df530a83))
* **cli:** added health checks and optional reqs to the docs for `lsof` and `ps`. Fixes [#89](https://github.com/assagman/ajans.nvim/issues/89) ([d403ec3](https://github.com/assagman/ajans.nvim/commit/d403ec3e695e17859e03aa0e6b4fe865140f7155))
* **cli:** added some config option validation ([c236b38](https://github.com/assagman/ajans.nvim/commit/c236b389819a3a11ada7234cd2a7a1be358b0785))
* **cli:** added terminal navigation with `<c-hjkl>`. Only mapped when not a float and a window in the dir exists. See [#51](https://github.com/assagman/ajans.nvim/issues/51) ([b48e177](https://github.com/assagman/ajans.nvim/commit/b48e177b20aeb422d3ea6838d8f2ca985ee6a21a))
* **cli:** deduplicate cli tool sessions. Closes [#92](https://github.com/assagman/ajans.nvim/issues/92) ([e5bcf17](https://github.com/assagman/ajans.nvim/commit/e5bcf171b13a99e53a8ac6b584baebf7c435584a))
* **cli:** handle special filenames for Claude, Gemini, Qwen. Fixes [#130](https://github.com/assagman/ajans.nvim/issues/130) ([19b5985](https://github.com/assagman/ajans.nvim/commit/19b59854782837430ae297ed4690660b7aa254d5))
* **config:** changed the default keymaps. Please check the updated documentation and example mappings ([6608705](https://github.com/assagman/ajans.nvim/commit/6608705fc6bd949efafbdeca879c63a5f933730c))
* **context:** you can now use context fallbacks like `{function|line}` ([076147a](https://github.com/assagman/ajans.nvim/commit/076147a6046836955712dcfc2702fc02c66684c9))
* **opencode:** add pid to external opencode sessions ([3d9d519](https://github.com/assagman/ajans.nvim/commit/3d9d519c90a2a071f56067a750840e6113359480))
* **terminal:** much better scrollback buffer. no flickering and should work in all modes ([3aa2fe5](https://github.com/assagman/ajans.nvim/commit/3aa2fe5d54f084cbfae591623f50cb8833a17f76))
* **terminal:** restore normal/terminal mode when entering the ajans window ([50c40d5](https://github.com/assagman/ajans.nvim/commit/50c40d52bf9e9f6aad0c0071fd44cc283ababf92))
* **terminal:** switch to scrollback when doing mouse scroll ([0dd3c3b](https://github.com/assagman/ajans.nvim/commit/0dd3c3bc4547b840f00fb2857e501d1efb254bf5))
* **tmux:** entering normal mode in a tmux terminal, now loads the whole tmux scrollback ([a453f76](https://github.com/assagman/ajans.nvim/commit/a453f76615bb49a1fbd25151a2229708a5187939))
* **tmux:** some tools won't process input if they don't have focus, so tools can now set `mux_focus = true` ([41dec4d](https://github.com/assagman/ajans.nvim/commit/41dec4dcdf0c8fe17f5f2e9eeced4645a88afb0d))
* **tool:** tools can now further format text before it's sent. See [#130](https://github.com/assagman/ajans.nvim/issues/130), see [#59](https://github.com/assagman/ajans.nvim/issues/59) ([28f8a07](https://github.com/assagman/ajans.nvim/commit/28f8a07a236dd0dea60942b3996465ddd29b770d))
* **util:** weak ref util method ([8036aea](https://github.com/assagman/ajans.nvim/commit/8036aeac392666e1b39d6c664f1741e813f74d49))


### Bug Fixes

* **cli.prompt:** proper way of rendering templates with highlights ([30b7b9e](https://github.com/assagman/ajans.nvim/commit/30b7b9ef72a1d78fbabf5484f4dc33adc3abb7d1))
* **cli.select:** sort terminal sessions before external sessions ([c487d53](https://github.com/assagman/ajans.nvim/commit/c487d532ed9245ddaaba0ef233e1a36565a38c78))
* **cli.state:** allow creating new sessions for tools that have only external sessions ([c588efb](https://github.com/assagman/ajans.nvim/commit/c588efbba7651446aaf767c1c7455804b30ad0e8))
* **cli:** allow sending a newlline `msg="\n"` ([fc0067a](https://github.com/assagman/ajans.nvim/commit/fc0067a2ee8c40188744e67c55d8e6c0b92fc8a4))
* **cli:** don't send empty messages ([63f626c](https://github.com/assagman/ajans.nvim/commit/63f626cd4490d61852009ea306dfb12845a412c3))
* **location:** different format that should work for most cli tools. Closes [#59](https://github.com/assagman/ajans.nvim/issues/59) ([d570e1f](https://github.com/assagman/ajans.nvim/commit/d570e1f83bf2a19e6c1fad5de9b1b07beb54b67d))
* **opencode:** check that open server is actually from an opencode process. Closes [#87](https://github.com/assagman/ajans.nvim/issues/87) ([cb8485a](https://github.com/assagman/ajans.nvim/commit/cb8485afa3be2221f06c66abcebff053572c2644))
* **procs:** handle case where `USER` is not set. Closes [#82](https://github.com/assagman/ajans.nvim/issues/82) ([01f89b7](https://github.com/assagman/ajans.nvim/commit/01f89b748349982906c65de3685a9fb7444c8748))
* **q:** filer procs on qchat instead of `q`, which seems to be the actual binary. Closes [#80](https://github.com/assagman/ajans.nvim/issues/80) ([4b65b8a](https://github.com/assagman/ajans.nvim/commit/4b65b8ad7e5e7e91e3db24a9061c6eb561fe2fd4))
* **qwen:** set `mux_focus = true` since qwen doesnt process input if unfocused. Fixes [#104](https://github.com/assagman/ajans.nvim/issues/104) ([c262b25](https://github.com/assagman/ajans.nvim/commit/c262b25be46de67b96ca38c005a97d7091025818))
* **sessions:** load tools during session setup, since thet may register session backends (like opencode) ([c7761eb](https://github.com/assagman/ajans.nvim/commit/c7761eb382af14e220933ad50cf23c559dfb3815))
* **terminal:** allow auto split width/height ([#111](https://github.com/assagman/ajans.nvim/issues/111)) ([03cf9fb](https://github.com/assagman/ajans.nvim/commit/03cf9fbe5fe23d4aeea981d62790ef54e307017e))
* **terminal:** better handling of crlf for send. See [#119](https://github.com/assagman/ajans.nvim/issues/119) ([7185e08](https://github.com/assagman/ajans.nvim/commit/7185e0863ba9f533b39d699243ee65c2f16062af))
* **terminal:** blur on hide ([81b2a85](https://github.com/assagman/ajans.nvim/commit/81b2a85543c5fd7fd19ce29169c99665e672c666))
* **terminal:** cleanup scrollback buffer ([9ef38db](https://github.com/assagman/ajans.nvim/commit/9ef38db6ea49fe04e2d237027e60cb96fe66af44))
* **terminal:** don't error when it's the last window and hiding. Closes [#124](https://github.com/assagman/ajans.nvim/issues/124) ([cab3ec4](https://github.com/assagman/ajans.nvim/commit/cab3ec49b751ad8aa3e1c743380accfe8f0798e8))
* **terminal:** keymap rhs fallback to rhs string ([2b644f0](https://github.com/assagman/ajans.nvim/commit/2b644f007ff59e9407ca8a12a400bcd896c1b096))
* **terminal:** no need to check for mouse scroll when we're not in terminal mode ([b52c3be](https://github.com/assagman/ajans.nvim/commit/b52c3beb608ae21079ac3800925e11a972cb76d9))
* **terminal:** only show scrollback when entering normal mode and the terminal window is current. Closes [#106](https://github.com/assagman/ajans.nvim/issues/106) ([1e03666](https://github.com/assagman/ajans.nvim/commit/1e036668600fc339fb69b406bab7227fdec668a2))
* **terminal:** remove padding since it causes issues with terminal reflow (Neovim bug) ([cc32068](https://github.com/assagman/ajans.nvim/commit/cc320688ed6015508f7b72a2770581e47ad972f6))
* **terminal:** safer way of entering terminal mode from scrollback buffer ([#129](https://github.com/assagman/ajans.nvim/issues/129)) ([2195213](https://github.com/assagman/ajans.nvim/commit/2195213ba29be1a5178e502076c1102958bd7283))
* **terminal:** safer way of entering terminal mode from scrollback buffer. Closes [#103](https://github.com/assagman/ajans.nvim/issues/103) ([0bc6f88](https://github.com/assagman/ajans.nvim/commit/0bc6f884ae4d807f5414b70d51a34fb813f588f9))
* **terminal:** scroll to last line in normal mode. Closes [#101](https://github.com/assagman/ajans.nvim/issues/101) ([69eb7b7](https://github.com/assagman/ajans.nvim/commit/69eb7b736798af9d382f1fc67df88e0450cf1529))
* **terminal:** send all text in one chunk with nvim_paste. Fixes [#119](https://github.com/assagman/ajans.nvim/issues/119). Fixes [#118](https://github.com/assagman/ajans.nvim/issues/118) ([ca97ecd](https://github.com/assagman/ajans.nvim/commit/ca97ecd0cface9913f942e3424aca767c6720445))
* **terminal:** use `nvim_paste` instead of `nvim_chan_send` to better simulate user input. Closes [#110](https://github.com/assagman/ajans.nvim/issues/110) ([cebcd44](https://github.com/assagman/ajans.nvim/commit/cebcd4415dc73e3713162e4ea317a6e91312f1a8))
* **terminal:** use nvim_put directly to paste into the terminal ([bed1d65](https://github.com/assagman/ajans.nvim/commit/bed1d65385e33bb0eae3fa4163b97606f2e4d8dc))
* **text:** handle empty virtual lines ([98a33eb](https://github.com/assagman/ajans.nvim/commit/98a33eb8c3550d4755570a2372e8cc573044711b))
* **tmux:** use `paste-buffer` with the `-r` flag to preserve newlines. Fixes [#93](https://github.com/assagman/ajans.nvim/issues/93) ([2fdc4d4](https://github.com/assagman/ajans.nvim/commit/2fdc4d482326035d9c5fe03f32ebeef84b63142c))
* **zellij:** attach to existing isolated session ([9deb771](https://github.com/assagman/ajans.nvim/commit/9deb7716ca1a60fa0644cbee10681ac9772f2c38))
* **zellij:** zellij:create -&gt; zellij:start ([4bd0df2](https://github.com/assagman/ajans.nvim/commit/4bd0df2694464b5fbe13a224bb5409f97e0af860))


### Performance Improvements

* **terminal:** only load scrollback buffer when needed ([628c3d0](https://github.com/assagman/ajans.nvim/commit/628c3d001e8697debdbd36dfed6441e7fe6fffc5))

## [1.3.0](https://github.com/assagman/ajans.nvim/compare/v1.2.0...v1.3.0) (2025-10-08)


### Features

* **context:** added quickfix context provider in CLI prompts ([#61](https://github.com/assagman/ajans.nvim/issues/61)) ([6c24d47](https://github.com/assagman/ajans.nvim/commit/6c24d47646ad3191a425bf646c0fe9396805d10a))
* **context:** added treesitter context `class`, `function`. You can add more in your config. ([8fb70e0](https://github.com/assagman/ajans.nvim/commit/8fb70e025a3dfd144944be7a1fa74b2af0e0f07d))
* **mux:** default to `tmux`, unless running inside a `zellij` session ([2110966](https://github.com/assagman/ajans.nvim/commit/2110966b5a2b76cb187b9bf80e23dd0b5327c8c7))
* **session:** attach to running tools in other tmux sessions ([#74](https://github.com/assagman/ajans.nvim/issues/74)) ([1de752c](https://github.com/assagman/ajans.nvim/commit/1de752c7c098e587928b193299c8a259f3499533))
* **tmux:** notify when starting a cli tool in a new window. ([c3d7572](https://github.com/assagman/ajans.nvim/commit/c3d7572c2dc0bb3d108debda5736c30909133433))
* **util:** Util.emit ([b0f3762](https://github.com/assagman/ajans.nvim/commit/b0f37629ac424cbde37d97066402506ea14dc1fa))


### Bug Fixes

* **cli:** fix insert mode for prompt action. Closes [#50](https://github.com/assagman/ajans.nvim/issues/50) ([8ebbd75](https://github.com/assagman/ajans.nvim/commit/8ebbd7578bcdd345b81ab0d3e6776133d6b0d140))
* **cli:** open cli window when started. Closes [#78](https://github.com/assagman/ajans.nvim/issues/78) ([b3560df](https://github.com/assagman/ajans.nvim/commit/b3560df49bd0a6d02a404a7a3ec8c57507861a3f))
* **cli:** properly propagate tool filter for show/toggle/focus. Closes [#57](https://github.com/assagman/ajans.nvim/issues/57) ([bc44db0](https://github.com/assagman/ajans.nvim/commit/bc44db09bbd5bd18551273d9349582b6e0f24bbc))
* **mux:** shorter session names. Fixes [#56](https://github.com/assagman/ajans.nvim/issues/56) ([a4e62ce](https://github.com/assagman/ajans.nvim/commit/a4e62cef32b6404bcbe4ef568d8a9d206b3cdaa8))
* **opencode:** onlny attach to existing opencode sessions on non-windows. Closes [#76](https://github.com/assagman/ajans.nvim/issues/76) ([063457e](https://github.com/assagman/ajans.nvim/commit/063457e154693ed532fb3c440b31066dde4d06b5))
* **opencode:** set back to system theme, since it is still not working for some ([b2818ec](https://github.com/assagman/ajans.nvim/commit/b2818ec5edffe061ce10ec3ca19c9896e418b32f))
* **session:** add optional detach() for session backends ([3aa531e](https://github.com/assagman/ajans.nvim/commit/3aa531e449965f5455b203c8356eb2f4e430adee))
* **session:** added detach ([7e88fa5](https://github.com/assagman/ajans.nvim/commit/7e88fa5672c4288c61548fe43e004dcd25ca4f84))
* **sessions:** better attached session tracking ([eaa7592](https://github.com/assagman/ajans.nvim/commit/eaa759204325abe4444a431517bb1ab697eadf0e))
* **state:** metatable to always get latest state through getters ([e0b32f5](https://github.com/assagman/ajans.nvim/commit/e0b32f59f2e03d0d67c0897c344a7d46f5d56e6a))
* **terminal:** use `exepath()` on windows. See [#53](https://github.com/assagman/ajans.nvim/issues/53) ([c307316](https://github.com/assagman/ajans.nvim/commit/c307316f77d80fbe92bd571c59ce1868703fe411))
* **terminal:** use shell on windows for jobstart when cmd is not an exe. See [#53](https://github.com/assagman/ajans.nvim/issues/53) ([3f1ccba](https://github.com/assagman/ajans.nvim/commit/3f1ccba5277417388a81598a4b7f08db849f29f7))
* **test:** treesitter woes in tests ([af931db](https://github.com/assagman/ajans.nvim/commit/af931dbda2efb19777810955c4563a6d0ce3201a))
* **tmux:** add detach-on-destroy option to tmux sessions ([#67](https://github.com/assagman/ajans.nvim/issues/67)) ([c525b13](https://github.com/assagman/ajans.nvim/commit/c525b1325b801b12f725ab4f2ae07b30676bdf54))
* **tmux:** set tool env vars. Closes [#62](https://github.com/assagman/ajans.nvim/issues/62) ([e869205](https://github.com/assagman/ajans.nvim/commit/e869205ff05a8defec31175e0f7f8f923e13cde6))
* **tmux:** use load-buffer instead of set-buffer to prevent issues with non-escaped text ([de62ed1](https://github.com/assagman/ajans.nvim/commit/de62ed1804897028cd3b0467f10d8f41dc8996db))

## [1.2.0](https://github.com/assagman/ajans.nvim/compare/v1.1.0...v1.2.0) (2025-10-02)


### Features

* added `:Ajans` command ([2f17d6b](https://github.com/assagman/ajans.nvim/commit/2f17d6bdf245381149b2515401a37ee67364904f))
* **cli.prompts:** when viewing the prompt select with snacks, you can copy with `<c-y>` and `y` in insert/normal mode ([f2098d9](https://github.com/assagman/ajans.nvim/commit/f2098d978dbf19a64283ebe98c901cae8c986960))
* **cli:** added Amazon Q ([e84c5d0](https://github.com/assagman/ajans.nvim/commit/e84c5d0df454ded38d6cd1982c8f689ebdde8b4e))
* **cli:** added proper multi-session management. you can now also resume mux sessions from other directories ([605c26b](https://github.com/assagman/ajans.nvim/commit/605c26b72eca9e310a67cb3ab8a4feaae4ca416f))
* **cli:** allow dynamic terminal configuration. Closes [#25](https://github.com/assagman/ajans.nvim/issues/25) ([6b265fa](https://github.com/assagman/ajans.nvim/commit/6b265faa39a182fb3fe0e92166232a330ed26d60))
* **cli:** allow overriding/adding keymaps per tool ([6def9f4](https://github.com/assagman/ajans.nvim/commit/6def9f4b1ae681c9b71c6ac054a67c0fe9773a4c))
* **cli:** lots of prompt/context improvements ([8a1f761](https://github.com/assagman/ajans.nvim/commit/8a1f76109b0a126a304151d64b540a7392ee08a7))
* **cli:** rework prompts/context and sending ([75b1897](https://github.com/assagman/ajans.nvim/commit/75b189707d087e8b142b10fd5dec8be03ef23ff4))
* **config:** added aider ([5144187](https://github.com/assagman/ajans.nvim/commit/514418756189083767177099d85768d72c21f103))
* **context:** lots of improvements to context including visual selection and proper previews ([7877322](https://github.com/assagman/ajans.nvim/commit/78773228c05461f40737680177de695e579b1ace))
* **terminal:** added full support for split / float layouts ([c93c0cb](https://github.com/assagman/ajans.nvim/commit/c93c0cbc2177a0eef19cf81adfe20329e4a90e83))
* **terminal:** set `ft=ajans_terminal` ([03366cc](https://github.com/assagman/ajans.nvim/commit/03366ccdcb9a58c140ad1c68c0da644d5d264f2f))
* **tmux:** disable status bar in ajans window ([#42](https://github.com/assagman/ajans.nvim/issues/42)) ([832165b](https://github.com/assagman/ajans.nvim/commit/832165bf84f40e3dd3a86c8d66835903e036013f))
* **tmux:** pass custom config file including user's config with a disabled status bar. Closes [#36](https://github.com/assagman/ajans.nvim/issues/36) ([6f06163](https://github.com/assagman/ajans.nvim/commit/6f0616359540fcbfa5cf2ae88cbdf2a028331a86))
* **tools:** added crush ([d6e25f3](https://github.com/assagman/ajans.nvim/commit/d6e25f370f9fd969158b40094bcbe7b75a776623))


### Bug Fixes

* **cli.context:** don't add a location for non-file buffers ([d72c611](https://github.com/assagman/ajans.nvim/commit/d72c611aa37b24d8ad401c4029d8946e27f53475))
* **cli.context:** get the correct buffer for providing context ([754ee76](https://github.com/assagman/ajans.nvim/commit/754ee7640ba32ce0e2350a3604ac85ea00865f45))
* **cli.context:** lastused sorting ([c448bb2](https://github.com/assagman/ajans.nvim/commit/c448bb2bd11fb1aaabd291eafe9759dc214c792e))
* **cli.crush:** use `<a-p>` for prompt instead of `<c-p>` for crush, since it's needed for its own functionality. Fixes [#17](https://github.com/assagman/ajans.nvim/issues/17) ([efbce7a](https://github.com/assagman/ajans.nvim/commit/efbce7a7110f7aa1592ab875fde7f724094bf3a7))
* **cli.prompts:** don't show empty rendered prompts in select ([d930586](https://github.com/assagman/ajans.nvim/commit/d930586085c970fe58356c2da9462572bb31d1dc))
* **cli:** fup ([094080d](https://github.com/assagman/ajans.nvim/commit/094080d5ca5b1dbe474cbdcefac63436881c8fe3))
* **cli:** prompt action ([8d9b06c](https://github.com/assagman/ajans.nvim/commit/8d9b06cabf5370f5e84798d86c84bc347cea859a))
* **cli:** removed some default keymaps since they clash with cli tools. Closes [#30](https://github.com/assagman/ajans.nvim/issues/30) ([8519d3b](https://github.com/assagman/ajans.nvim/commit/8519d3b777b39273e8734ab9e00f1c4e39805896))
* **cli:** set proper TERM for cli tools. Fixes [#37](https://github.com/assagman/ajans.nvim/issues/37) ([7608be2](https://github.com/assagman/ajans.nvim/commit/7608be2a532fe663e471bf23483e6537e73a0d51))
* **mux:** `M:_sessions` -&gt; `M._sessions` ([c73cc39](https://github.com/assagman/ajans.nvim/commit/c73cc397cf4c01df774815d4f5e089390be3a59b))
* **mux:** better commands to get existing sessions ([feea2b2](https://github.com/assagman/ajans.nvim/commit/feea2b2560cd9229f72bef74e0d0e69754c34d5f))
* **opencode:** remove hack since it's no longer needed. See [#16](https://github.com/assagman/ajans.nvim/issues/16) ([f2dcd16](https://github.com/assagman/ajans.nvim/commit/f2dcd16641ebb7bedc86b3211d3f97c84954d4ae))
* **opencode:** work-around for opencode rendering artifacts by forcing `system` theme. See [#16](https://github.com/assagman/ajans.nvim/issues/16) ([d29fbc9](https://github.com/assagman/ajans.nvim/commit/d29fbc90a3593ffcd00244a8c48a6dd373013353))
* **terminal:** change initial delay from 2 seconds to 500 ms ([c7948f1](https://github.com/assagman/ajans.nvim/commit/c7948f12ae9c77433c95b701e46f05728e90cc44))
* **terminal:** check for exit code ~= 0 ([5bd2d01](https://github.com/assagman/ajans.nvim/commit/5bd2d0163b3bbe35c4f7b464cf9b070c33e1c59f))
* **terminal:** don't automatically close the terminal window when the command exited too quickly ([52a6ed4](https://github.com/assagman/ajans.nvim/commit/52a6ed40d312726a45ffc191fdc81791c4d928f5))
* **terminal:** don't close when cli tool exits too quickly ([63ec164](https://github.com/assagman/ajans.nvim/commit/63ec164ea9e88731b1fc69533eefe908731a625d))
* **terminal:** set winfixwidth and winfixheight when needed ([09dbae1](https://github.com/assagman/ajans.nvim/commit/09dbae13046193bf83d23e23297c678b62591424))
* **terminal:** startinsert on focus and stopinsert on blur ([5e9f9da](https://github.com/assagman/ajans.nvim/commit/5e9f9da7bd53d4777a3ee1ff94f8355473d1ab4b))
* **terminal:** use vim environ instead of uv ([0d99706](https://github.com/assagman/ajans.nvim/commit/0d997060670028544438fa3eb4d26c04492af1e7))
* **zellij:** disable session serialization for AI tools ([71d17b9](https://github.com/assagman/ajans.nvim/commit/71d17b92648b84fbe654fec07934fd5dbef330e4))

## [1.1.0](https://github.com/assagman/ajans.nvim/compare/v1.0.0...v1.1.0) (2025-09-29)


### Features

* **cli:** added ai tool urls ([51431b1](https://github.com/assagman/ajans.nvim/commit/51431b158c2cf76d65fcfd4166d29b7486b0999f))
* **cli:** added blur/is_focused ([614c08c](https://github.com/assagman/ajans.nvim/commit/614c08c00b71b56f2b2e99189ebf2a41e7127951))
* **cli:** added cli.blur to defocus the terminal window ([4e465c0](https://github.com/assagman/ajans.nvim/commit/4e465c0113166f43467c55ca1a5e42cd58b5eb45))
* **cli:** added custom snacks options for `vim.ui.select` ([8e8677c](https://github.com/assagman/ajans.nvim/commit/8e8677c2ea53feeb47f05bdcb3d02e1038a32dbb))
* **cli:** added support for starting AI cli tools in a zellij or tmux session ([0385dbf](https://github.com/assagman/ajans.nvim/commit/0385dbf7f597a27c14de99ee594670008fdf9b7a))
* **cli:** added toggle focus ([c83ebd5](https://github.com/assagman/ajans.nvim/commit/c83ebd52501a230276c9fa8b86657d044517a379))
* **cli:** added watcher to let Neovim know when an AI tool updated any buffers ([c1083fa](https://github.com/assagman/ajans.nvim/commit/c1083faba3e9f4b5cc53c610564c43bbb9bbfc4f))
* **cli:** AI cli tools integration ([ab5da08](https://github.com/assagman/ajans.nvim/commit/ab5da081ae5ba579c306f20de5e3598c7045151f))
* **cli:** cli tool keymaps ([ac353d4](https://github.com/assagman/ajans.nvim/commit/ac353d4be53a44cc05350c35f4d2bd41e116f328))
* **config:** added opencode and cursor to tools ([c11c1b9](https://github.com/assagman/ajans.nvim/commit/c11c1b98e364b4c28c8a940526b8118663555f05))
* **health:** add multiplexer checks ([a903fb1](https://github.com/assagman/ajans.nvim/commit/a903fb1ecaec153c3975a6de204c7f9da22e739e))
* **util:** debug logging ([6315c92](https://github.com/assagman/ajans.nvim/commit/6315c927a7c7913c8c9954c6d23b4e7830ddcc1e))
* **util:** debug notify ([9454ee7](https://github.com/assagman/ajans.nvim/commit/9454ee78ecbbaf416682ccf24830912cb7e3b153))
* **watch:** added config flag to enable/disable watch ([8a8c1ae](https://github.com/assagman/ajans.nvim/commit/8a8c1aeda4c98c434e109cd6a96b1aafd9957627))


### Bug Fixes

* **cli:** tag buffer for context ([08e67b8](https://github.com/assagman/ajans.nvim/commit/08e67b8d724a2a29bda89a6c3e97e8875c84a594))
* **cli:** toggle with focus by default ([c8e60d7](https://github.com/assagman/ajans.nvim/commit/c8e60d7802372f28761b5da189224ea20c4337ae))
* **context:** border cases ([ee09859](https://github.com/assagman/ajans.nvim/commit/ee09859a5e68bebfdfe890a15a889455070d2c54))
* **snacks:** load module instead of using global ([77bf35f](https://github.com/assagman/ajans.nvim/commit/77bf35f4ee4f41dbc40b739fa2d988e0fcf27bc9))
* **terminal:** open window before running cli tool. Fixes [#5](https://github.com/assagman/ajans.nvim/issues/5) ([4e4928c](https://github.com/assagman/ajans.nvim/commit/4e4928c7a271befe27e3b5a541951e93efd95eaa))
* **treesitter:** one-off with getting text before first highlight ([5e79172](https://github.com/assagman/ajans.nvim/commit/5e79172f947daf6e748e063f1283f795fafbdf23))
* **ui:** show only one sign ([f4545fa](https://github.com/assagman/ajans.nvim/commit/f4545faa29a02ddaf6ac8752b81d219ace7b4640))
* **watch:** disable debug ([cd69b41](https://github.com/assagman/ajans.nvim/commit/cd69b416dba425053545f5518610aa6d5e310de2))

## 1.0.0 (2025-09-27)


### Features

* **health:** added health check ([1f72350](https://github.com/assagman/ajans.nvim/commit/1f7235019511b04c4482d870966f2261955a1654))
* initial commit ([9464193](https://github.com/assagman/ajans.nvim/commit/94641937514c21c657128e76f474c03bd971ba58))
* **treesitter.slice:** allow to to be nil ([0bb097e](https://github.com/assagman/ajans.nvim/commit/0bb097ec52b88f2b67ea91ccef472709f72d8761))
* **treesitter:** update leading/trailing/eol whitespace hl_group ([6cf8067](https://github.com/assagman/ajans.nvim/commit/6cf8067fdb7aa4721d16fceade93936a37d42c37))
* **util:** split_words / split_chars ([5335ad9](https://github.com/assagman/ajans.nvim/commit/5335ad94baca9463dc02a6c767bda057dcf99992))
