import type { RenderEngine } from './RenderEngine';
import { ThreeEngine } from './ThreeEngine';

// Rejestr silników — nowy silnik = dopisanie tutaj, zero zmian w UI
const registry: Record<string, () => RenderEngine> = {
  three: () => new ThreeEngine(),
};

export function createEngine(id = import.meta.env.VITE_RENDER_ENGINE ?? 'three'): RenderEngine {
  const factory = registry[id];
  if (!factory) throw new Error(`Unknown engine: ${id}`);
  return factory();
}
