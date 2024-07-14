For developing any kind of plugin using `lazy.nvim` you basically just need to do this:
- clone the repo into your workspace so that lua LSP can find dependencies (this should be your config directory if you want type hints to pass through properly)
- point the plugin to local directory
- update the plugin using `:Lazy` and confirm it's looking at the local directory

```
{
  'chottolabs/kznllm.nvim',
  dev = true,
  dir = '/home/chottolabs/.config/nvim/plugins/kznllm.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  ...
},
```
