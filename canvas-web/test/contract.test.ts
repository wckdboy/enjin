import { readdirSync, readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { Request, Response, nativeToWeb, webToNative } from "../src/bridge/schema";

const dir = new URL("../../shared/bridge-fixtures/", import.meta.url).pathname;
const all = { ...nativeToWeb, ...webToNative } as Record<string, { params: { parse(x: unknown): unknown }; result: { parse(x: unknown): unknown } }>;

describe("bridge fixtures", () => {
  const files = readdirSync(dir).filter((f) => f.endsWith(".json"));
  it("cover every method", () => {
    expect(files.map((f) => f.replace(/\.json$/, "")).sort()).toEqual(Object.keys(all).sort());
  });
  for (const f of files) {
    it(`${f} matches the schema`, () => {
      const fx = JSON.parse(readFileSync(dir + f, "utf8"));
      const req = Request.parse(fx.request);
      all[req.method]!.params.parse(req.params);
      const res = Response.parse(fx.response);
      expect("result" in res).toBe(true);
      all[req.method]!.result.parse((res as { result: unknown }).result);
    });
  }
});
