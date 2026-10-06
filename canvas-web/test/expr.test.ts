import { describe, expect, it } from "vitest";
import { compileExpr } from "../src/live/expr";

describe("compileExpr", () => {
  const ev = (s: string, v: Record<string, number> = {}) => compileExpr(s)(v);
  it("does arithmetic with precedence", () => {
    expect(ev("1 + 2 * 3")).toBe(7);
    expect(ev("(1 + 2) * 3")).toBe(9);
    expect(ev("2 ^ 3 ^ 2")).toBe(512);
    expect(ev("-2 ^ 2")).toBe(-4);
    expect(ev("10 % 4")).toBe(2);
  });
  it("uses variables, constants and whitelisted functions", () => {
    expect(ev("B * I * L", { B: 0.5, I: 2, L: 0.3 })).toBeCloseTo(0.3);
    expect(ev("2 * pi * r", { r: 1 })).toBeCloseTo(2 * Math.PI);
    expect(ev("sqrt(2 * g * h)", { h: 5 })).toBeCloseTo(Math.sqrt(98.1));
    expect(ev("max(a, b, 3)", { a: 1, b: 7 })).toBe(7);
    expect(ev("F = m × a".split("=")[1]!, { m: 2, a: 3 })).toBe(6);
  });
  it("has comparisons and a ternary", () => {
    expect(ev("v > 3 ? 1 : 0", { v: 4 })).toBe(1);
    expect(ev("v >= 3 && v < 5", { v: 5 })).toBe(0);
  });
  it("refuses anything that isn't a formula", () => {
    for (const bad of ["alert(1)", "constructor.constructor('x')()", "a.b", "'s'", "1 +", "x[0]"]) {
      expect(() => compileExpr(bad)({}), bad).toThrow();
    }
  });
});
