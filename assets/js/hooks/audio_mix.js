// Hook LiveView : joue plusieurs extraits en même temps, retire les pistes trouvées,
// et gère les effets (sons synthétisés + confettis).
//
// Événements serveur :
//   "mix:start" {tracks: [{id, url}]}, "mix:stop" {id}, "mix:stop_all"
//   "fx:found" {id, kind: "title" | "artist"}, "fx:miss", "fx:end"
//
// Les navigateurs (Safari surtout) n'autorisent le son qu'après un geste utilisateur.
// Au clic sur un bouton [data-unlock], on "réveille" 5 éléments <audio> avec un silence
// et on crée le contexte Web Audio utilisé pour les effets sonores.

const SILENCE =
  "data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEARKwAAIhYAQACABAAZGF0YQAAAAA=";
const POOL_SIZE = 5;
const MAX_START_OFFSET = 8; // secondes : décalage aléatoire dans l'extrait de 30 s
const DUCK_LEVEL = 0.3; // part du volume de la musique gardée pendant un effet sonore
const CONFETTI_COLORS = ["#ff4d8d", "#ffd23f", "#2de2e6", "#5cff9d", "#a66cff", "#ff8a3d"];

export const AudioMix = {
  mounted() {
    this.pool = [];
    this.active = new Map();
    this.ctx = null;
    this.lastFx = 0;

    this.el.addEventListener("click", (e) => {
      if (e.target.closest("[data-unlock]")) this.unlock();
    });

    // Vide la zone de saisie après envoi (le serveur ne l'écrase pas tant qu'elle a le focus).
    this.el.addEventListener("submit", (e) => {
      setTimeout(() => {
        const input = e.target.querySelector("input[name=guess]");
        if (input) input.value = "";
      }, 0);
    });

    this.handleEvent("mix:start", ({ tracks }) => this.start(tracks));
    this.handleEvent("mix:stop", ({ id }) => this.fadeOut(id));
    this.handleEvent("mix:stop_all", () => this.stopAll());

    this.handleEvent("fx:found", ({ id, kind }) => this.found(id, kind));
    this.handleEvent("fx:miss", () => this.miss());
    this.handleEvent("fx:end", () => setTimeout(() => this.sfx("end"), 450));
  },

  destroyed() {
    this.stopAll();
  },

  unlock() {
    while (this.pool.length < POOL_SIZE) this.pool.push(new Audio());
    const playing = new Set(this.active.values());

    this.pool.forEach((audio) => {
      if (playing.has(audio)) {
        // Manche déjà lancée (room multijoueur) : on relance ce que le navigateur a bloqué.
        if (audio.paused) audio.play().catch(() => {});
      } else {
        audio.src = SILENCE;
        audio.play().catch(() => {});
      }
    });
    this.audioCtx();
  },

  // --- Mix des extraits -----------------------------------------------------

  start(tracks) {
    this.stopAll();
    while (this.pool.length < tracks.length) this.pool.push(new Audio());

    // Volume par piste réduit pour éviter la saturation quand tout joue ensemble.
    const volume = Math.min(1, 1.4 / Math.sqrt(tracks.length));
    this.musicVolume = volume;
    clearTimeout(this.duckTimer);
    clearInterval(this.duckRamp);

    tracks.forEach((track, i) => {
      const audio = this.pool[i];
      audio.pause();
      audio.loop = true;
      audio.volume = volume;
      audio.src = track.url;
      audio.addEventListener(
        "loadedmetadata",
        () => {
          audio.currentTime = Math.random() * MAX_START_OFFSET;
        },
        { once: true }
      );
      audio.play().catch((err) => console.warn("Lecture bloquée", err));
      this.active.set(track.id, audio);
    });
  },

  fadeOut(id) {
    const audio = this.active.get(id);
    if (!audio) return;
    this.active.delete(id);

    const step = audio.volume / 10;
    const timer = setInterval(() => {
      if (audio.volume - step <= 0) {
        clearInterval(timer);
        audio.pause();
      } else {
        audio.volume -= step;
      }
    }, 60);
  },

  stopAll() {
    this.active.forEach((audio) => audio.pause());
    this.active.clear();
  },

  // --- Effets sonores (synthétisés, aucun fichier à charger) ----------------

  audioCtx() {
    try {
      if (!this.ctx) {
        const AC = window.AudioContext || window.webkitAudioContext;
        if (AC) {
          this.ctx = new AC();
          // Bus des effets : compresseur (évite la saturation quand les notes se
          // superposent) puis gain général, au-dessus du niveau de la musique.
          const comp = this.ctx.createDynamicsCompressor();
          comp.threshold.value = -12;
          comp.knee.value = 6;
          comp.ratio.value = 6;
          comp.attack.value = 0.003;
          comp.release.value = 0.15;
          this.fxBus = this.ctx.createGain();
          this.fxBus.gain.value = 1.4;
          comp.connect(this.fxBus).connect(this.ctx.destination);
          this.fxIn = comp;
        }
      }
      if (this.ctx && this.ctx.state === "suspended") this.ctx.resume();
    } catch (_) {
      this.ctx = null;
    }
    return this.ctx;
  },

  tone(freq, at, dur, { type = "sine", gain = 0.2, slideTo = null } = {}) {
    const ctx = this.audioCtx();
    if (!ctx) return;

    const t0 = ctx.currentTime + at;
    const osc = ctx.createOscillator();
    const amp = ctx.createGain();

    osc.type = type;
    osc.frequency.setValueAtTime(freq, t0);
    if (slideTo) osc.frequency.exponentialRampToValueAtTime(slideTo, t0 + dur);

    amp.gain.setValueAtTime(0.0001, t0);
    amp.gain.exponentialRampToValueAtTime(gain, t0 + 0.01);
    amp.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);

    osc.connect(amp).connect(this.fxIn || ctx.destination);
    osc.start(t0);
    osc.stop(t0 + dur + 0.02);
  },

  sfx(name) {
    switch (name) {
      case "title": // arpège montant, victoire complète
        this.duck(650);
        [523.25, 659.25, 783.99, 1046.5].forEach((f, i) =>
          this.tone(f, i * 0.07, 0.24, { type: "triangle", gain: 0.6 })
        );
        break;
      case "artist": // deux notes, bonne réponse partielle
        this.duck(450);
        this.tone(659.25, 0, 0.14, { type: "triangle", gain: 0.55 });
        this.tone(987.77, 0.09, 0.26, { type: "triangle", gain: 0.55 });
        break;
      case "miss": // petit "bzzt" grave
        this.duck(300);
        this.tone(220, 0, 0.22, { type: "sawtooth", gain: 0.22, slideTo: 110 });
        break;
      case "end": // fanfare de fin de manche
        this.duck(1200);
        [392, 523.25, 659.25, 783.99].forEach((f, i) =>
          this.tone(f, i * 0.12, 0.35, { type: "square", gain: 0.2 })
        );
        this.tone(1046.5, 0.5, 0.6, { type: "triangle", gain: 0.55 });
        break;
    }
  },

  // Baisse la musique le temps d'un effet sonore, puis la remonte en douceur :
  // le feedback reste audible même quand les 5 pistes jouent fort.
  duck(ms) {
    const base = this.musicVolume || 1;
    this.active.forEach((audio) => (audio.volume = base * DUCK_LEVEL));

    clearTimeout(this.duckTimer);
    clearInterval(this.duckRamp);
    this.duckTimer = setTimeout(() => {
      let level = DUCK_LEVEL;
      this.duckRamp = setInterval(() => {
        level = Math.min(1, level + 0.1);
        this.active.forEach((audio) => (audio.volume = base * level));
        if (level >= 1) clearInterval(this.duckRamp);
      }, 30);
    }, ms);
  },

  found(id, kind) {
    // Plusieurs pistes trouvées d'un coup : un seul son, mais des confettis pour chacune.
    const now = performance.now();
    if (now - this.lastFx > 120) this.sfx(kind);
    this.lastFx = now;
    this.confetti(id, kind);
  },

  miss() {
    this.sfx("miss");
    // Formulaire de saisie, en solo (#guess-form) comme en room (#room-guess-form).
    const form = this.el.querySelector(".bm-form");
    if (!form) return;
    form.classList.remove("bm-shake");
    void form.offsetWidth; // relance l'animation
    form.classList.add("bm-shake");
  },

  // --- Confettis ------------------------------------------------------------

  confetti(id, kind) {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const el = document.getElementById(`slot-${id}`);
    if (!el) return;

    const r = el.getBoundingClientRect();
    const cx = r.left + r.width / 2;
    const cy = r.top + r.height / 2;
    const count = kind === "title" ? 40 : 24;

    for (let i = 0; i < count; i++) {
      const size = 6 + Math.random() * 7;
      const p = document.createElement("div");
      Object.assign(p.style, {
        position: "fixed",
        left: `${cx}px`,
        top: `${cy}px`,
        width: `${size}px`,
        height: `${size * 0.6}px`,
        background: CONFETTI_COLORS[i % CONFETTI_COLORS.length],
        borderRadius: "2px",
        pointerEvents: "none",
        zIndex: 9999,
      });
      document.body.appendChild(p);

      const angle = Math.random() * Math.PI * 2;
      const dist = 60 + Math.random() * (r.width / 2.4);
      const dx = Math.cos(angle) * dist * 1.3;
      const dy = Math.sin(angle) * dist - 50;
      const spin = Math.random() * 720 - 360;

      p.animate(
        [
          { transform: "translate(0, 0) rotate(0deg)", opacity: 1 },
          { transform: `translate(${dx}px, ${dy + 130}px) rotate(${spin}deg)`, opacity: 0 },
        ],
        { duration: 700 + Math.random() * 600, easing: "cubic-bezier(.2,.8,.4,1)" }
      ).onfinish = () => p.remove();
    }
  },
};
