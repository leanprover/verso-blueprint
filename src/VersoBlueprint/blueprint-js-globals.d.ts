export {};

declare global {
  interface Window {
    VersoBlueprint?: {
      slides?: Record<string, unknown>;
    };
    bpTexPreludeTable?: Record<string, string>;
    Reveal?: {
      on?: (event: string, fn: (event: { currentSlide?: Element }) => void) => void;
    };
  }

  const katex: {
    render: (tex: string, element: Element, options?: Record<string, unknown>) => void;
  };
}
