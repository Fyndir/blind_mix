// Hook LiveView : joue plusieurs extraits en même temps et retire les pistes trouvées.
//
// Événements serveur : "mix:start" {tracks: [{id, url}]}, "mix:stop" {id}, "mix:stop_all"
//
// Les navigateurs (Safari surtout) n'autorisent la lecture audio qu'après un geste
// utilisateur. Au clic sur un bouton [data-unlock], on "réveille" 5 éléments <audio>
// avec un silence ; on les réutilise ensuite pour les vraies pistes.

const SILENCE =
  "data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEARKwAAIhYAQACABAAZGF0YQAAAAA=";
const POOL_SIZE = 5;
const MAX_START_OFFSET = 8; // secondes : décalage aléatoire dans l'extrait de 30 s

export const AudioMix = {
  mounted() {
    this.pool = [];
    this.active = new Map();

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
  },

  destroyed() {
    this.stopAll();
  },

  unlock() {
    while (this.pool.length < POOL_SIZE) this.pool.push(new Audio());
    this.pool.forEach((audio) => {
      audio.src = SILENCE;
      audio.play().catch(() => {});
    });
  },

  start(tracks) {
    this.stopAll();
    while (this.pool.length < tracks.length) this.pool.push(new Audio());

    // Volume par piste réduit pour éviter la saturation quand tout joue ensemble.
    const volume = Math.min(1, 1.4 / Math.sqrt(tracks.length));

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
};
