# ByteBrew Web Export

Ships the [ByteBrew](https://www.bytebrew.io/) Web SDK into Godot Web exports
without ever needing the SDK's `node_modules` (~65MB, mostly build tooling
like `ts-loader` that your project never runs) inside the Godot project.

## How it works

`bytebrew.bundle.js` in this folder is a single, self-contained, minified
build of the `bytebrew-web-sdk` npm package (~25KB). `bytebrew_export_plugin.gd`
is a Godot `EditorExportPlugin` that runs automatically on every **Web**
export and writes that one file directly into the export output
directory, next to `index.html` -- no manual copy step, no post-export
script.

It does this in `_export_end()` by writing straight to disk at the real
output path Godot reports in `_export_begin()`. `EditorExportPlugin.add_file()`
looks like the obvious API for this, but its `path` argument is a
*virtual* path used to load the file through Godot's own resource
system (i.e. it lands inside the `.pck`), not a real file on disk next
to `index.html` -- so it silently does not do what a plain
`<script src="...">` tag on the page needs.

Your `custom_shell.html` just needs a plain script tag plus the small
init/track wiring (see "Adding this to a new project" below). Because the
bundle loads as a normal (non-module) script, it sets a global:
`window.ByteBrewSDK.ByteBrew`, with the same static methods documented at
<https://docs.bytebrew.io/sdk/javascript> (e.g. `initializeByteBrew`,
`newCustomEvent`, `isByteBrewInitialized`, ...).

## Adding this to a new project

1. Copy this whole `addons/bytebrew_web_export/` folder into the new
   project.
2. Enable the plugin: Project Settings > Plugins > "ByteBrew Web Export".
3. In that project's `custom_shell.html`, add this near the bottom, before
   the Engine bootstrap `<script>` block that calls `engine.startGame()`:

   ```html
   <script src="bytebrew.bundle.js"></script>
   <script>
	   // Bind initialization and tracking methods globally onto the window object
	   window.initByteBrew = function(appId, sdkKey, appVersion) {
		   try {
			   window.ByteBrewSDK.ByteBrew.initializeByteBrew(appId, sdkKey, appVersion);
			   console.log("ByteBrew JS SDK initialized successfully.");
		   } catch (e) {
			   console.error("Failed to initialize ByteBrew:", e);
		   }
	   };

	   window.trackCustomEvent = function(eventName, parametersJSON) {
		   try {
			   const params = parametersJSON ? JSON.parse(parametersJSON) : {};
			   window.ByteBrewSDK.ByteBrew.newCustomEvent(eventName, params);
		   } catch (e) {
			   console.error("Failed to track ByteBrew event:", e);
		   }
	   };
   </script>
   ```

4. Have a GDScript autoload call `window.initByteBrew(appId, sdkKey, appVersion)`
   via `JavaScriptBridge.get_interface("window")` on startup (see
   `Singletons/ByteBrew.gd` in the math-machine project for a working
   example), and `window.trackCustomEvent(name, JSON.stringify(params))` for
   events.

## Rebuilding bytebrew.bundle.js

Rebuild this whenever ByteBrew ships an SDK update. Requires Node.js/npm.
Do this in a throwaway scratch folder -- **not** inside the Godot project --
since `npm install` will pull down the full ~65MB `node_modules` tree:

```sh
mkdir /tmp/bytebrew-build && cd /tmp/bytebrew-build
npm init -y
npm install bytebrew-web-sdk
npm install --save-dev esbuild

cat > entry.js << 'EOF'
const { ByteBrew } = require('bytebrew-web-sdk');
window.ByteBrewSDK = { ByteBrew };
EOF

npx esbuild entry.js --bundle --minify --platform=browser --format=iife --outfile=bytebrew.bundle.js
```

Then copy the resulting `bytebrew.bundle.js` over the one in this folder.
You can delete the whole `/tmp/bytebrew-build` scratch folder afterwards --
none of it needs to persist.

## Why this exists

Godot's Web export doesn't copy arbitrary loose project files next to
`index.html` on its own -- only what's referenced through the export
plugin API (`add_file`) or embedded directly in the HTML shell ends up
there. A `<script src="...">` tag in `custom_shell.html` that points at a
project file won't resolve unless something puts that file next to
`index.html` at export time, which is exactly what this plugin automates.

Separately (and independent of file size), `bytebrew-web-sdk` is
distributed as an npm package meant to be consumed via `import { ByteBrew }
from "bytebrew-web-sdk"` inside a bundler-based project. That bare import
specifier can't be resolved by a browser loading a plain `<script
type="module">` with no bundler or import map behind it -- it has to be
bundled into a self-contained file first, which is what
`bytebrew.bundle.js` is.
