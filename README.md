# mylsp

A Language Server built for the educational purpose of understanding WHAT LSP is and HOW it works.

Built by referencing:
- [repo](https://github.com/tjdevries/educationalsp)
- [video](https://www.youtube.com/watch?v=YsdlcQoHqPY)
But it was built instead in [odin](https://odin-lang.org/)

To set it up in my config NvChad:

```lua
local configs = require("lspconfig.configs")

if not configs.mylsp then
  configs.mylsp = {
    default_config = {
      cmd = { "/path/to/mylsp/mylsp" },
      filetypes = { "markdown" },
      single_file_support = true,
    },
  }

  lspconfig.mylsp.setup {
    on_attach = on_attach,
    capabilities = capabilities,
  }
end
```

```md
It likes auto completing `Neovim (BTW)` and approving the word `Neovim`

It likes to error `VS Code` and offer code completions for it

Going to defintion moves you a line up
```
