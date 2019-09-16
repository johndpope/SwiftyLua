# SwiftyLua
Swift&lt;->Lua Bridge Framework (iOS)

The intention is to seperate application logic into Lua and let Swift to handle the *hard* part. Similar to what have done in many *scriptable* games, the engine will deal with underlying game loop, rendering, user input, event detection etc., and leave the game logic to the script. Decouple policy from mechanism gives both part the felexibiltiy to evlove without breaking the other side.

## Init

```swift
import SwiftyLua

// in the app delegate, define a property
let swiftyLua = SwiftyLuaBridge("init")
```
where "init.lua" is the entry point for all the .lua script. 

You can add some app logic here to load different script (e.g. for testing):
```swift
let swiftyLua = SwiftyLuaBridge(UserDefaults.standard.luaBridgeDebug ? "playground/main" : "init")
```
will load the debug playground based on the settings.

## Importing Swift Classes

`SwiftLuaBridge` is defined as: 
```swift
class SwiftyLuaBridge {
    var bridge: LuaBridge

    init(_ script: String) {
        self.bridge = LuaBridge(start: script) { L, bridge, trait in
            
            bridge.reg(Foo.self)
                .ctor("init", trait.static(Foo.init))
                .property("val", trait.prop(\Foo.val))
                
            // ...
       }
   }
```

later in Lua: 
```lua
local foo = Foo:init()
print(foo.var)
```


