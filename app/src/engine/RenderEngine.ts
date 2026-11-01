// PORT — stały kontrakt silnika graficznego (wymienialny przez adaptery)
export interface ProductConfig {
  color?: string;
  metalness?: number;
  roughness?: number;
  autoRotate?: boolean;
}

export interface EngineCapabilities {
  maxTextureSize: number;
  supportsDraco: boolean;
}

export interface RenderEngine {
  id: string;
  capabilities: EngineCapabilities;
  init(canvas: HTMLCanvasElement): Promise<void>;
  /** zwraca funkcję czyszczącą */
  loadModel(url: string): Promise<() => void>;
  /** chmura punktów (np. ze skanu X9) */
  loadPointCloud(data: PointCloudData): Promise<() => void>;
  applyConfig(config: ProductConfig): void;
  screenshot(): Promise<Blob>;
  dispose(): void;
}

export interface PointCloudData {
  positions: Float32Array; // xyz
  colors?: Uint8Array;     // rgb 0-255
  pointCount: number;
  bboxMin: [number, number, number];
  bboxMax: [number, number, number];
}
