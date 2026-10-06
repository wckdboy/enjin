import { Excalidraw } from "@excalidraw/excalidraw";
import type { ExcalidrawImperativeAPI } from "@excalidraw/excalidraw/types";
import { useEffect, useRef, useState } from "react";
import type { Bridge } from "./bridge/client";
import { PROTOCOL_VERSION } from "./bridge/schema";
import { ensureFonts } from "./fonts";
import { commitStroke } from "./ink/InkService";
import { InputGate } from "./inputGate";
import { PortalController } from "./portal/PortalController";

const EXCALIDRAW_VERSION = "0.18.1";

export function App({ bridge }: { bridge: Bridge }) {
  const [api, setApi] = useState<ExcalidrawImperativeAPI | null>(null);
  const [fatal, setFatal] = useState<string | null>(null);
  const stageRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!api || !stageRef.current) return;
    const gate = new InputGate();
    const portals = new PortalController(api, bridge, gate, stageRef.current);
    bridge.on("portal.load", (p) => portals.load(p).then(() => null));
    bridge.on("canvas.applyOps", (p) => portals.applyOps(p));
    bridge.on("canvas.frame", (p) => portals.frame(p.cardId));
    bridge.on("canvas.flash", (p) => portals.flash(p.cardId).then(() => null));
    bridge.on("ink.lock", ({ locked }) => {
      if (locked) gate.block("ink");
      else gate.unblock("ink");
      return null;
    });
    bridge.on("ink.commit", (p) => commitStroke(api, p));
    bridge.install();
    // Handle for Safari Web Inspector and Playwright.
    (window as unknown as { __enjinDebug: unknown }).__enjinDebug = { api, portals, gate };
    ensureFonts()
      .then(() => bridge.request("canvas.ready", { protocolVersion: PROTOCOL_VERSION, excalidrawVersion: EXCALIDRAW_VERSION }))
      .then((r) => !r.accepted && setFatal(r.reason ?? "Native rejected this canvas build."))
      .catch((e) => setFatal(`Handshake failed: ${String(e)}`));
    return () => portals.dispose();
  }, [api, bridge]);

  if (fatal) return <div className="fatal">{fatal}</div>;
  return (
    <div className="stage" ref={stageRef}>
      <Excalidraw
        excalidrawAPI={setApi}
        handleKeyboardGlobally={false}
        UIOptions={{
          canvasActions: { loadScene: false, saveToActiveFile: false, export: false, saveAsImage: false, toggleTheme: null, clearCanvas: false },
          tools: { image: false },
        }}
        initialData={{ appState: { viewBackgroundColor: "#fffdf8", currentItemRoughness: 0 } }}
      />
    </div>
  );
}
