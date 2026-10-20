# Zigine release packaging

The release package contains:

- the platform-native Zigine editor executable;
- a matching Zig compiler and `lib/zig` standard library/runtime;
- SDL3 and raylib project templates;
- the default Zigine assets.

# Build a native unix/linux package with:

```sh
./scripts/package.sh
```

# On Windows, run PowerShell as administrator:

```powershell
.\scripts\package.ps1
```

The optional target argument is a Zig target triple. The editor can be
cross-compiled, but the bundled Zig compiler must be native to the operating
system that will run the package. For a cross-build, provide matching runtime
paths with `ZIGINE_RUNTIME_ZIG` and `ZIGINE_RUNTIME_LIB_DIR`.


### Proper Native MacOS will be added later.
albeit if you are on a mac, you are free to try the unix/linux shell script!
