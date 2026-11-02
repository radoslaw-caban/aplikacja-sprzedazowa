// PORT — stały kontrakt silnika graficznego (wymienialny przez adaptery)
export interface ProductConfig {
  color?: string;
  metalness?: number;
  roughness?: number;
  autoRotate?: boolean;
  /** tryb gizma dla modelu GLB nakładanego na chmurę */
  gizmoMode?: 'translate' | 'rotate' | 'scale';
  showModel?: boolean;
  /** rozmiar punktu chmury w metrach */
  pointSize?: number;
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
  /** włącza/wyłącza gizmo przesuwania modelu względem chmury */
  setGizmoMode?(mode: 'translate' | 'rotate' | 'scale' | null): void;
  applyConfig(config: ProductConfig): void;
  screenshot(): Promise<Blob>;
  dispose(): void;
}

export interface PointCloudData {
  positions: Float32Array; // xyz
  colors?: Uint8Array;     // rgb 0-255
  pointCount: number;
  /** opcjonalne — silnik i tak liczy bbox z przefiltrowanych punktów */
  bboxMin?: [number, number, number];
  bboxMax?: [number, number, number];
}
