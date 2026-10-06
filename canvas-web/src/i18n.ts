// The canvas's own words. Native tells us the language (canvas.setLanguage).
export type Lang = "en" | "da";

const words = {
  findingPicture: { en: "finding a picture…", da: "finder et billede…" },
  diveIn: { en: "dive in →", da: "dyk ind →" },
  inside: { en: (n: number) => `${n} inside →`, da: (n: number) => `${n} indeni →` },
  actionDive: { en: "Dive in", da: "Dyk ind" },
  actionOpen: { en: "Open", da: "Åbn" },
  fig: {
    en: { flow: "Process", cycle: "Cycle", timeline: "Timeline", bars: "Compare", parts: "Parts", stat: "Number", formula: "Formula", code: "Code" },
    da: { flow: "Proces", cycle: "Kredsløb", timeline: "Tidslinje", bars: "Sammenlign", parts: "Dele", stat: "Tal", formula: "Formel", code: "Kode" },
  },
} as const;

let current: Lang = "en";
const listeners = new Set<(l: Lang) => void>();

export function lang(): Lang {
  return current;
}

export function setLang(l: Lang): void {
  if (l === current) return;
  current = l;
  listeners.forEach((f) => f(l));
}

export function onLangChange(f: (l: Lang) => void): () => void {
  listeners.add(f);
  return () => listeners.delete(f);
}

export const t = {
  findingPicture: () => words.findingPicture[current],
  diveIn: () => words.diveIn[current],
  inside: (n: number) => words.inside[current](n),
  actionDive: () => words.actionDive[current],
  actionOpen: () => words.actionOpen[current],
  fig: (kind: keyof (typeof words.fig)["en"]) => words.fig[current][kind],
};
