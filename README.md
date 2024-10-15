# cheese (in development)

## simple cross-platform command line parser for zig applications

![Preview](resources/preview.png)

it targets the ease of usage: 

- single function call to get args
- flexible parsing
- minimalistic source

## add to your project

fetch into your project:
``` bash
cd into_your_project_or_create_it_with_zig_init
zig fetch --save https://github.com/varikoz272/cheese/archive/refs/tags/latest_version_for_example_1.0.0.tar.gz
```

in build.zig:
```zig
// can paste it wherever
const cheese = b.dependency("cheese", .{});
exe.root_module.addImport("cheese", cheese.module("cheese"));
```

in *.zig:
```zig
const cheese = @import("cheese");
```
