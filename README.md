# cheese

## simple cross-platform command line parser for zig applications

![Preview](resources/preview.png)

it targets the ease of usage: 

- single function call to get args
- flexible parsing
- small amount of code

## currently in development

## add to your project

### via mods folder

clone into your project:
``` bash
mkdir mods
cd mods
git clone https://github.com/varikoz272/cheese.git
cd ..
```

in build.zig:
```zig
const cheese = b.addModule("cheese", .{
    .root_source_file = b.path("./mods/cheese/cheese/Parser.zig"),
});

exe.root_module.addImport("cheese", cheese);
```

in *.zig:
```zig
const cheese = @import("cheese");
```

fetching will be implemented later
