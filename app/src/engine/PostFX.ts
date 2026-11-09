import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { GTAOPass } from 'three/addons/postprocessing/GTAOPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { SMAAPass } from 'three/addons/postprocessing/SMAAPass.js';

/**
 * Pipeline post-processingu — to on odpowiada za „fotograficzny" wygląd:
 *  1. GTAO — ambient occlusion (ciemne zakamarki, kontakt brył z podłogą)
 *  2. Bloom — subtelne rozlewanie światła na jasnych płaszczyznach
 *  3. Vignette + kontrast — winieta obiektywu i delikatne podbicie kontrastu
 *  4. SMAA — wygładzanie krawędzi
 * Bez tych warstw render zawsze wygląda „jak gra", bo brakuje mu
 * globalnego zaciemnienia i odpowiedzi kamery.
 */

const GradeShader = {
  uniforms: {
    tDiffuse: { value: null as THREE.Texture | null },
    vignette: { value: 0.14 },
    contrast: { value: 1.02 },
    saturation: { value: 1.0 },
    lift: { value: 0.02 },
  },
  vertexShader: /* glsl */ `
    varying vec2 vUv;
    void main() {
      vUv = uv;
      gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
    }
  `,
  fragmentShader: /* glsl */ `
    uniform sampler2D tDiffuse;
    uniform float vignette;
    uniform float contrast;
    uniform float saturation;
    uniform float lift;
    varying vec2 vUv;

    void main() {
      vec4 tex = texture2D(tDiffuse, vUv);
      vec3 c = tex.rgb;

      // kontrast wokół 0.5 (bez zmiany jasności整体)
      c = (c - 0.5) * contrast + 0.5;
      // nasycenie
      float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
      c = mix(vec3(l), c, saturation);
      // lekki lift w cieniach — brak „mlecznych" czerni
      c += lift * (1.0 - c);

      // winieta obiektywu
      vec2 d = vUv - 0.5;
      float v = 1.0 - vignette * dot(d, d) * 2.2;
      c *= clamp(v, 0.0, 1.0);

      gl_FragColor = vec4(c, tex.a);
    }
  `,
};

export interface PostOptions {
  ao?: boolean;
  bloom?: boolean;
  grade?: boolean;
}

export class PostFX {
  composer: EffectComposer;
  private gtao?: GTAOPass;
  private bloom?: UnrealBloomPass;
  private grade?: ShaderPass;

  constructor(renderer: THREE.WebGLRenderer, scene: THREE.Scene, camera: THREE.PerspectiveCamera) {
    this.composer = new EffectComposer(renderer);
    this.composer.addPass(new RenderPass(scene, camera));

    // --- ambient occlusion ---
    this.gtao = new GTAOPass(scene, camera, 1024, 1024);
    this.gtao.output = GTAOPass.OUTPUT.Default;
    this.gtao.blendIntensity = 0.55;
    this.gtao.updateGtaoMaterial({
      radius: 0.42,
      distanceExponent: 1.4,
      thickness: 1.2,
      scale: 1.0,
      samples: 8,
      distanceFallOff: 1.0,
      screenSpaceRadius: false,
    });
    this.gtao.updatePdMaterial({
      lumaPhi: 10,
      depthPhi: 2,
      normalPhi: 3,
      radius: 6,
      rings: 2,
      samples: 8,
    });
    this.composer.addPass(this.gtao);

    // --- bloom (delikatny) ---
    this.bloom = new UnrealBloomPass(new THREE.Vector2(1024, 1024), 0.12, 0.45, 1.15);
    this.composer.addPass(this.bloom);

    // --- korekcja barw + winieta ---
    this.grade = new ShaderPass(GradeShader);
    this.composer.addPass(this.grade);

    // --- wygładzanie krawędzi ---
    const smaa = new SMAAPass();
    this.composer.addPass(smaa);

    this.composer.addPass(new OutputPass());
  }

  setSize(width: number, height: number, pixelRatio = 1) {
    this.composer.setPixelRatio(pixelRatio);
    this.composer.setSize(width, height);
    this.gtao?.setSize(width, height);
    this.bloom?.setSize(width, height);
  }

  render() {
    this.composer.render();
  }

  set(options: PostOptions) {
    if (options.ao !== undefined && this.gtao) this.gtao.enabled = options.ao;
    if (options.bloom !== undefined && this.bloom) this.bloom.enabled = options.bloom;
    if (options.grade !== undefined && this.grade) this.grade.enabled = options.grade;
  }

  dispose() {
    this.composer.dispose();
  }
}
