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

You need to map the function, property to the desired name on Lua side; as show above, `trait` (of type: `FuncTrait`) will do the heavy lifting, and you need to tell SwiftyLua different type of the importing (.static, .prop, .instance)

later in Lua: 
```lua
local foo = Foo:init()
print(foo.var)
```

## Importing Enum

```swift
bridge.reg(DiskType.self, .Enum)
                .enum(DiskType.Dropbox, "Dropbox")
                .enum(DiskType.GoogleDrive, "GoogleDrive")
                .enum(DiskType.OneDrive, "OneDrive")
                .enum(DiskType.Mega, "Mega")
                .enum(DiskType.Box, "Box")
                .method("createDiskClient", trait.instance(DiskType.createDiskClient))
                .property("icon", trait.prop(\DiskType.icon))
```

And in Lua: 
```lua
let dropbox = DiskType.Dropbox:createDiskClient()
```

## Importing ObjC Class

## For method with Closure Parameter 

Class like `PHAsset` has method with closure parameter: `scanStorageSize(progress:complete:))`. To call this method in Lua, we need to wrap the `progress` and `complete` callback function from Lua and ensure the arguments matches the signature and handle the reference count of captured object correctly.

Also, it's common that the closure is called on a different thread than the caller. Thus, the bridge need to create new `LuaState` on different thread if necessory.

We do this via `.block` (e.g. `.block(((UInt, UInt, AssetNode)->Int).self)`)

```swift
bridge.reg(PHAsset.self)
                .property("filename", trait.prop(\PHAsset.filename))
                .s_method("scanInfinityAlbum_", trait.static(PHAsset.scanInfinityAlbum(_:)))
                    .block(((PHAsset?, MakerNote?, Int, Int, Void) -> Int).self)
                .s_method("scanStorageSizeProgress_complete_", trait.static(PHAsset.scanStorageSize(progress:complete:)))
                    .block(((UInt, UInt, AssetNode)->Int).self)
                    .block(((UInt64, [AssetNode], [AssetNode], [AssetNode])->()).self)
```
