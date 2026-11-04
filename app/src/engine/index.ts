import type { RenderEngine } from './RenderEngine';
import { ThreeEngine } from './ThreeEngine';

/**
 * Rejestr silników — nowy silnik = dopisanie jednej linii, zero zmian w UI.
 * Oba wpisy korzystają z adaptera three.js, ale w różnych trybach renderowania;
 * podmiana na Babylon/WebGPU polega na dodaniu kolejnego adaptera implementującego port.
 */
const registry: Record<string, (mode: 'pbr' | 'wireframe') => RenderEngine> = {
  three: (mode) => new ThreeEngine(mode),
  wireframe: () => new ThreeEngine('wireframe'),
};

export function createEngine(
  id = import.meta.env.VITE_RENDER_ENGINE ?? 'three',
  mode: 'pbr' | 'wireframe' = id === 'wireframe' ? 'wireframe' : 'pbr',
): RenderEngine {
  const factory = registry[id] ?? registry.three;
  return factory(mode);
}

export const ENGINE_IDS = Object.keys(registry);
