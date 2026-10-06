// Must be set before Excalidraw loads fonts. An absolute base, because custom
// schemes (enjin://) have an opaque origin and "/" would resolve to nothing.
window.EXCALIDRAW_ASSET_PATH = new URL("./", window.location.href).toString();

import "@excalidraw/excalidraw/index.css";
import "./style.css";
import { createRoot } from "react-dom/client";
import { Bridge, webkitTransport } from "./bridge/client";
import { devHost } from "./bridge/devHost";
import { App } from "./App";

let bridge: Bridge;
bridge = new Bridge(webkitTransport() ?? devHost(() => bridge));

window.addEventListener("error", (e) => bridge.notify("log.event", { level: "error", message: e.message }));
window.addEventListener("unhandledrejection", (e) => bridge.notify("log.event", { level: "error", message: String(e.reason) }));

createRoot(document.getElementById("root")!).render(<App bridge={bridge} />);
