import {
  ErrorCode,
  PROTOCOL_VERSION,
  Request as RequestSchema,
  Response,
  nativeToWeb,
  webToNative,
  type NativeToWeb,
  type Params,
  type Request,
  type Result,
  type WebToNative,
} from "./schema";

/** Something that can answer web->native requests (WKWebView or the dev host). */
export interface NativeTransport {
  post(req: Request): Promise<unknown>;
}

type Handler<K extends keyof NativeToWeb> = (params: Params<NativeToWeb, K>) => Promise<Result<NativeToWeb, K>> | Result<NativeToWeb, K>;

declare global {
  interface Window {
    webkit?: { messageHandlers?: { enjin?: { postMessage(msg: unknown): Promise<unknown> } } };
    /** Entry point native calls via callAsyncJavaScript. */
    enjin?: { handle(req: unknown): Promise<Response> };
  }
}

export class BridgeError extends Error {
  constructor(public code: number, message: string) {
    super(message);
  }
}

export class Bridge {
  private seq = 0;
  private handlers = new Map<string, (params: unknown) => Promise<unknown>>();

  constructor(private transport: NativeTransport) {}

  /** Call a native method. Params and result are validated against the schema. */
  async request<K extends keyof WebToNative>(method: K, params: Params<WebToNative, K>): Promise<Result<WebToNative, K>> {
    const spec = webToNative[method];
    const req: Request = { v: PROTOCOL_VERSION, id: `w${++this.seq}`, method, params: spec.params.parse(params) };
    const raw = await this.transport.post(req);
    const res = Response.parse(raw);
    if ("error" in res) throw new BridgeError(res.error.code, res.error.message);
    return spec.result.parse(res.result) as Result<WebToNative, K>;
  }

  /** Fire-and-forget; failures are logged to the console, never thrown. */
  notify<K extends keyof WebToNative>(method: K, params: Params<WebToNative, K>): void {
    this.request(method, params).catch((e) => console.warn(`[bridge] ${method} failed`, e));
  }

  on<K extends keyof NativeToWeb>(method: K, handler: Handler<K>): void {
    const spec = nativeToWeb[method];
    this.handlers.set(method, async (params) => spec.result.parse(await handler(spec.params.parse(params) as Params<NativeToWeb, K>)));
  }

  /** Dispatch a native->web request. Never throws; errors become JSON-RPC errors. */
  async handle(raw: unknown): Promise<Response> {
    const id = typeof raw === "object" && raw && "id" in raw ? String((raw as { id: unknown }).id) : "?";
    const fail = (code: number, message: string): Response => ({ v: PROTOCOL_VERSION, id, error: { code, message } });
    let req: Request;
    try {
      req = RequestSchema.parse(raw);
    } catch (e) {
      return fail(ErrorCode.invalidParams, `malformed request: ${String(e)}`);
    }
    if (req.v !== PROTOCOL_VERSION) return fail(ErrorCode.versionMismatch, `web speaks v${PROTOCOL_VERSION}, got v${req.v}`);
    const handler = this.handlers.get(req.method);
    if (!handler) return fail(ErrorCode.methodNotFound, `unknown method ${req.method}`);
    try {
      return { v: PROTOCOL_VERSION, id: req.id, result: (await handler(req.params)) ?? null };
    } catch (e) {
      const code = e instanceof Error && e.name === "ZodError" ? ErrorCode.invalidParams : ErrorCode.internal;
      return fail(code, e instanceof Error ? e.message : String(e));
    }
  }

  /** Expose `window.enjin.handle` for native. */
  install(): void {
    window.enjin = { handle: (req) => this.handle(req) };
  }
}

export function webkitTransport(): NativeTransport | null {
  const h = window.webkit?.messageHandlers?.enjin;
  return h ? { post: (req) => h.postMessage(req) } : null;
}
