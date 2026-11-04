// PORT — stały kontrakt silnika graficznego (wymienialny przez adaptery)
import type { SceneBox } from '../design/types';

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
  /** render listy brył (projektanta szafek) */
  renderBoxes?(boxes: SceneBox[], origin?: { x: number; z: number }): void;
  /** kadrowanie kamery na projekt */
  frameDesign?(): void;
  /** raycast po bryłach projektu */
  pickAt?(clientX: number, clientY: number): {
    cabinetId?: string;
    elementId?: string;
    frontId?: string;
    kind?: string;
    screen: { x: number; y: number };
    point: [number, number, number];
  } | null;
  /** kamera do wnętrza: przed szafkę albo do szuflady */
  frameInterior?(
    cabinet: { x: number; z: number; width: number; height: number; depth: number; rotation: number },
    view: 'front' | 'drawer',
    elementY?: number,
  ): void;
  /** ustawienia widoku: oddalenie, FOV, obrót projektu, widoczność frontów */
  setViewSettings?(o: {
    distance?: number;
    fov?: number;
    autoRotate?: boolean;
    frontsVisible?: boolean;
  }): void;
  /** pomieszczenie testowe */
  renderRoom?(boxes: import('../design/room').RoomBox[], visible?: boolean): void;
  /** punkt na podłodze pod kursorem (mm) */
  screenToFloor?(clientX: number, clientY: number): { x: number; z: number } | null;
  /** linie dociągania */
  drawGuides?(guides: { axis: 'x' | 'z'; value: number; from: number; to: number }[]): void;
  clearGuides?(): void;
  highlightCabinet?(cabinetId: string | null): void;
  setCloudVisible?(visible: boolean): void;
  setWallGhost?(on: boolean): void;
  highlightElement?(elementId: string | null): void;
  disposeDesign?(): void;
  getDebugInfo?(): Record<string, unknown>;
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

export type { SceneBox, ElementKind, CabinetElement, Cabinet, Cutout } from '../design/types';
export type { RoomBox } from '../design/room';
