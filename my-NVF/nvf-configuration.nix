{ pkgs, lib, ... }:

{
  vim = {
    theme = {
      enable = true;
      name = "catppuccin";
      style = "mocha";
    };
    autocomplete = {
      blink-cmp = {
        enable = false;
        mappings = {
          confirm = "<C-Return>";
        };
      };
      nvim-cmp = {
        enable = true;
        mappings = {
          confirm = "<C-Return>";
        };
      };
    };
    autopairs.nvim-autopairs.enable = true;
    binds = {
      whichKey = {
        enable = true;
      };
    };
    clipboard = {
      enable = true;
      providers.wl-copy.enable = true;
    };

    dashboard = {
      alpha = {
        enable = true;
      };
    };

    debugger = {
      nvim-dap = {
        enable = false;
      };
    };
    filetree = {
      nvimTree = {
        enable = true;
        mappings = {
          toggle = "<TT>";
        };
      };
    };
    formatter = {
      conform-nvim.enable = true;
    };
    fzf-lua.enable = true;
    git.enable = true;
    git.gitsigns.enable = true;
    lsp = {
      enable = true;
      formatOnSave = true;
      harper-ls.enable = false;
    };
    notify = {
      nvim-notify = {
        enable = true;
      };
    };
    projects = {
      project-nvim.enable = true;
    };
    statusline = {
      lualine = {
        enable = true;
      };
    };
    tabline = {
      nvimBufferline = {
        enable = true;
        mappings = {
          cycleNext = "<C-L>";
          cyclePrevious = "<C-H>";
        };
      };
    };
    telescope = {
      enable = true;
      extensions = [
        {
          name = "fzf";
          packages = [ pkgs.vimPlugins.telescope-fzf-native-nvim ];
          setup = {
            fzf = {
              fuzzy = true;
            };
          };
        }
      ];
    };

    treesitter = {
      enable = true;
      autotagHtml = true;
      context.enable = true;
    };
    languages = {
      nix.enable = true;
      enableDAP = false;
      clang = {
        enable = true;
        lsp = {
          enable = true;
        };
        treesitter = {
          enable = true;
        };
        dap = {
          enable = false;
        };
      };
      zig = {
        enable = true;
        lsp = {
          enable = true;
        };
        treesitter = {
          enable = true;
        };
      };
      python = {
        enable = false;
        lsp = {
          enable = false;
          servers = [ "ruff" ];
        };
        treesitter = {
          enable = false;
        };
        dap = {
          enable = false;
        };
      };
      java = {
        enable = false;
        lsp = {
          enable = false;
        };
        treesitter = {
          enable = false;
        };
      };
      ts = {
        enable = false;
        lsp = {
          enable = false;
        };
        treesitter = {
          enable = false;
        };
      };
      tailwind = {
        enable = false;
        lsp = {
          enable = false;
        };
      };
      rust = {
        enable = false;
        lsp = {
          enable = false;
        };
        treesitter = {
          enable = false;
        };
        dap = {
          enable = false;
        };
      };
      markdown = {
        enable = true;
        lsp = {
          enable = true;
        };
        treesitter = {
          enable = true;
        };
        extensions = {
          markview-nvim = {
            enable = true;
          };
        };
      };
      json = {
        enable = true;
        format.enable = true;
        lsp = {
          enable = true;
        };
        treesitter = {
          enable = true;
        };
      };
      assembly = {
        enable = true;
        lsp = {
          enable = true;
        };
        treesitter = {
          enable = true;
        };
      };
    };
    utility = {
      ccc = {
        enable = true;
      };
      crazy-coverage = {
        enable = true;
      };
      motion = {
        flash-nvim.enable = true;
      };
      multicursors.enable = true;
      nix-develop.enable = true;
      oil-nvim.enable = true;
      outline = {
        aerial-nvim.enable = true;
      };
      surround = {
        enable = true;
      };
      undotree.enable = true;
      yanky-nvim.enable = true;
      yanky-nvim.setupOpts.ring.storage = "sqlite";
    };
    visuals = {
      blink-indent = {
        enable = true;
      };
      cinnamon-nvim.enable = true;
      nvim-cursorline.enable = true;
      nvim-web-devicons.enable = true;
    };
    ui = {
      noice = {
        enable = true;
      };
      breadcrumbs = {
        enable = true;
      };
      illuminate = {
        enable = true;
      };
    };
    undoFile.enable = true;
    keymaps = [

    ];
  };
}
