# SwiftyLua
Swift&lt;->Lua Bridge Framework (iOS)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

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

## Calling Swift from Lua

### Importing Swift Classes

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

### Importing Enum

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

### Importing ObjC Class

OjbC class importing is easy:
```swift
bridge.reg(UIImage.self)
```
No need to register the methods, SwiftyLua will laverage ObjC runtime to forward to the right method at the calling point in Lua. 

### For method with Closure Parameter 

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

To call in Lua:
```lua
PHAsset.scanStorageSizeProgress_complete_(function (index, total, node)
		print('progress bg ', index, total, index/total)
		return math.max(math.floor(total/100), 1)
	end, function (size, new, delete, edit)
		print('complete size scan: ', size, #new, #delete, #edit)
        return true
    end)
```

## Calling Lua from Swift

To define a class in Lua, use the `class` function (`InfDiskCollectionModel` is sub class of `NSObject` and conform to `LuaDiskCollectionModel` protocol):
```lua
-- define Lua class InfDiskCollectionModel, callable from Swift side as LuaDiskCollectionModel
_ENV = class {'InfDiskCollectionModel', 'NSObject', {'LuaDiskCollectionModel'}}

function create(self)
	return self:init()
end

function init(self)
	local obj = self.__ctor()
	
	obj.model = {
		DiskType.Dropbox,
		DiskType.GoogleDrive,
	}
	
	return obj
end

-- collection data source
function numberOfSectionsInCollectionView_(self, collection)
	return 1
end

function collectionView_numberOfItemsInSection_(self, collection, section)
	print('collection: #item')
	return #self.model
end

```

`LuaDiskCollectionModel` is defined as an ObjC protocol:
```Objc
@protocol LuaDiskCollectionModel <NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
+ (id<LuaDiskCollectionModel>) create;
@end
```

`LuaDiskCollectionModel` will work as a collection view data source. And to create it on Swift side:
```Swift
let disks_model_cls: LuaDiskCollectionModel.Type = InfL.DiskCollectionModel.lclass()
let disks_model: LuaDiskCollectionModel = disks_model_cls.create()
```
Then you can plug the disks_model onto the collection view to act as its data source. 

## Still in Development
SwiftLua is forked from an internal project (photo storage with cloud sync) and is still in developing. It's stable enough for daily scripting, but defintely there're a lot of places to improve for better integration with Swift (e.g. interface generation, better handling of `Optional` & `enum`). So all comments are welcomed. 

Happy Lua Scripting!
