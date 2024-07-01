For developing any kind of plugin using `lazy.nvim` you basically just need to do this:
- clone the repo
- comment out or delete the original repo specifier
- point the plugin to local directory
- update the plugin using `:Lazy` and confirm it's looking at the local directory

```
{
  --'chottolabs/kznllm.nvim',
  dev = true,
  dir = '/home/chottolabs/gh-projects/kznllm.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  ...
},
```
