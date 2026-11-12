defmodule BlindMixWeb.Pop do
  @moduledoc """
  Thème visuel « pop » du jeu (fond sombre, couleurs vives, animations).

  Les couleurs de texte sont toutes définies explicitement : le thème clair/sombre
  de Phoenix ne peut donc plus donner du texte blanc sur fond blanc.
  Utilisation : `<BlindMixWeb.Pop.styles />` en haut d'une page.
  """
  use Phoenix.Component

  @css ~S"""
  :root{--bm-ink:#fff;--bm-deep:#1b1035;--bm-pink:#ff4d8d;--bm-yellow:#ffd23f;--bm-cyan:#2de2e6;--bm-green:#5cff9d;--bm-violet:#a66cff;--bm-orange:#ff8a3d}
  body{margin:0;min-height:100vh;color:#fff;background:radial-gradient(circle at 12% 8%,#43217f 0,transparent 45%),radial-gradient(circle at 88% 92%,#7d1f5e 0,transparent 45%),#140c2b;background-attachment:fixed;font-family:ui-rounded,"Nunito","Segoe UI",system-ui,sans-serif}
  .bm-wrap{max-width:42rem;margin:0 auto;padding:1.5rem 1rem 4rem;display:flex;flex-direction:column;gap:1.25rem;color:#fff}
  .bm-stack{display:flex;flex-direction:column;gap:1.25rem;min-width:0}
  .bm-head{display:flex;align-items:center;justify-content:space-between;gap:1rem}
  .bm-title{margin:0;font-size:1.9rem;font-weight:900;letter-spacing:-.02em;line-height:1.1;background:linear-gradient(90deg,var(--bm-yellow),var(--bm-pink),var(--bm-violet));-webkit-background-clip:text;background-clip:text;color:transparent}
  .bm-title--xl{font-size:2.8rem;text-align:center}
  .bm-link{color:#d9cdfa;font-size:.9rem;text-decoration:underline;background:none;border:0;cursor:pointer}
  .bm-link:hover{color:#fff}
  .bm-lead{margin:0;font-size:1.1rem;line-height:1.5;color:#e9e2ff}
  .bm-center{text-align:center}
  .bm-card{background:rgba(255,255,255,.07);border:2px solid rgba(255,255,255,.14);border-radius:1.25rem;padding:1.25rem;display:flex;flex-direction:column;gap:1rem;color:#fff}
  .bm-error{margin:0;padding:.8rem 1rem;border-radius:1rem;background:#ffd9e0;color:#6b0f2a;font-weight:700;border:2px solid var(--bm-pink)}

  .bm-btn{display:inline-block;cursor:pointer;border:0;border-radius:999px;padding:.9rem 1.6rem;font-size:1.05rem;font-weight:900;text-decoration:none;text-align:center;color:var(--bm-deep);background:var(--bm-yellow);box-shadow:0 6px 0 #b8890a;transition:transform .08s,box-shadow .08s}
  .bm-btn:hover{transform:translateY(-2px);box-shadow:0 8px 0 #b8890a}
  .bm-btn:active{transform:translateY(4px);box-shadow:0 2px 0 #b8890a}
  .bm-btn[disabled]{opacity:.55;cursor:wait}
  .bm-btn--spotify{background:var(--bm-green);box-shadow:0 6px 0 #1f9e57}
  .bm-btn--spotify:hover{box-shadow:0 8px 0 #1f9e57}
  .bm-btn--spotify:active{box-shadow:0 2px 0 #1f9e57}
  .bm-btn--deezer{background:var(--bm-violet);box-shadow:0 6px 0 #6a3fc2}
  .bm-btn--deezer:hover{box-shadow:0 8px 0 #6a3fc2}
  .bm-btn--deezer:active{box-shadow:0 2px 0 #6a3fc2}
  .bm-row{display:flex;flex-wrap:wrap;gap:1rem;justify-content:center}

  .bm-hud{display:flex;align-items:center;justify-content:space-between;gap:1rem}
  .bm-score{font-weight:900;font-size:1rem;color:#d9cdfa;text-transform:uppercase;letter-spacing:.08em}
  .bm-score-num{display:inline-block;margin-left:.4rem;font-size:2.4rem;color:var(--bm-yellow);text-shadow:0 3px 0 rgba(0,0,0,.35);animation:bm-bump .6s cubic-bezier(.2,1.6,.4,1)}
  .bm-timer{font-weight:900;font-size:1.2rem;padding:.35rem .9rem;border-radius:999px;background:rgba(255,255,255,.12);color:#fff}
  .bm-timer--low{background:var(--bm-pink);color:#fff;animation:bm-pulse .6s ease-in-out infinite}
  .bm-bar{height:10px;border-radius:999px;background:rgba(255,255,255,.12);overflow:hidden}
  .bm-bar-fill{height:100%;border-radius:999px;background:linear-gradient(90deg,var(--bm-cyan),var(--bm-green));transition:width 1s linear}
  .bm-bar-fill--low{background:linear-gradient(90deg,var(--bm-orange),var(--bm-pink))}
  .bm-banner{padding:1rem 1.2rem;border-radius:1.25rem;background:linear-gradient(135deg,var(--bm-yellow),var(--bm-orange));color:var(--bm-deep);font-weight:900;font-size:1.15rem;text-align:center;animation:bm-pop .7s cubic-bezier(.2,1.6,.4,1)}

  .bm-slots{display:flex;flex-direction:column;gap:.9rem}
  .bm-slot{position:relative;display:flex;flex-wrap:wrap;align-items:center;gap:1rem;padding:1rem 1.1rem;border-radius:1.25rem;border:3px solid var(--c);background:rgba(36,20,71,.92);color:#fff;box-shadow:0 8px 0 rgba(0,0,0,.28);overflow:hidden}
  .bm-slot--playing{box-shadow:0 0 26px color-mix(in srgb,var(--c) 50%,transparent),0 8px 0 rgba(0,0,0,.28)}
  .bm-slot--title{border-color:#fff;background:linear-gradient(135deg,#5cff9d,#2de2e6);color:#0b2a22;animation:bm-pop .75s cubic-bezier(.2,1.6,.4,1)}
  .bm-slot--artist{border-color:#fff;background:linear-gradient(135deg,#2de2e6,#a66cff);color:#10163a;animation:bm-pop .75s cubic-bezier(.2,1.6,.4,1)}
  .bm-slot--missed{border-style:dashed;border-color:#ff7a99;background:rgba(255,255,255,.06);color:#ffd9e0;animation:bm-shake .5s}
  .bm-num{flex:none;width:2.6rem;height:2.6rem;border-radius:50%;display:grid;place-items:center;font-size:1.4rem;font-weight:900;background:var(--c);color:var(--bm-deep)}
  .bm-slot--title .bm-num,.bm-slot--artist .bm-num{background:#fff}
  .bm-body{flex:1 1 8rem;min-width:0}
  .bm-name{font-size:1.25rem;font-weight:900;line-height:1.2;overflow-wrap:anywhere}
  .bm-mystery{font-size:1.25rem;font-weight:900;letter-spacing:.04em;color:var(--c)}
  .bm-sub{font-size:.95rem;font-weight:700;opacity:.85;overflow-wrap:anywhere}
  .bm-chip{flex:none;padding:.3rem .8rem;border-radius:999px;font-weight:900;font-size:.9rem;background:var(--bm-deep);color:#fff}
  .bm-chip--miss{background:#5a1a33;color:#ffd9e0}
  .bm-float{position:absolute;right:1rem;top:.6rem;font-size:1.6rem;font-weight:900;color:#fff;text-shadow:0 2px 0 rgba(0,0,0,.35);pointer-events:none;animation:bm-float 1.1s ease-out forwards}
  .bm-eq{flex:none;display:flex;align-items:flex-end;gap:3px;height:30px}
  .bm-eq i{display:block;width:6px;height:100%;border-radius:3px;background:var(--c);transform-origin:bottom;animation:bm-eq .9s ease-in-out infinite}
  .bm-eq i:nth-child(2){animation-delay:.15s}
  .bm-eq i:nth-child(3){animation-delay:.3s}
  .bm-eq i:nth-child(4){animation-delay:.45s}
  .bm-eq i:nth-child(5){animation-delay:.6s}

  .bm-form{display:flex;gap:.6rem}
  .bm-form.bm-shake{animation:bm-shake .45s}
  .bm-input{flex:1;min-width:0;padding:.95rem 1.2rem;border-radius:999px;border:3px solid transparent;background:#fff;color:var(--bm-deep);font-size:1.1rem;font-weight:800;box-shadow:0 5px 0 rgba(0,0,0,.28)}
  .bm-input::placeholder{color:#7d6ba6;font-weight:700}
  .bm-input:focus{outline:none;border-color:var(--bm-pink)}
  .bm-feedback{margin:0;padding:.6rem 1rem;border-radius:1rem;background:rgba(255,255,255,.1);color:#fff;font-weight:700;animation:bm-in .35s ease-out}

  .bm-dev{flex-basis:100%;display:flex;flex-wrap:wrap;gap:.5rem}
  .bm-dev button,.bm-devbtn{cursor:pointer;padding:.3rem .7rem;border-radius:.7rem;border:2px dashed var(--bm-orange);background:rgba(255,138,61,.15);color:#ffd2b0;font-size:.8rem;font-weight:800}
  .bm-dev button:hover,.bm-devbtn:hover{background:rgba(255,138,61,.35);color:#fff}

  .bm-nav{max-width:42rem;margin:0 auto;padding:1rem 1rem 0;display:flex;align-items:center;justify-content:space-between;gap:.75rem;flex-wrap:wrap}
  .bm-brand{display:inline-flex;align-items:center;gap:.5rem;font-weight:900;font-size:1.15rem;color:#fff;text-decoration:none;letter-spacing:-.01em}
  .bm-logo{display:grid;place-items:center;width:2.1rem;height:2.1rem;border-radius:50%;background:linear-gradient(135deg,var(--bm-yellow),var(--bm-pink));color:var(--bm-deep);font-size:1.1rem;box-shadow:0 3px 0 rgba(0,0,0,.3);transition:transform .2s cubic-bezier(.2,1.6,.4,1)}
  .bm-brand:hover .bm-logo{transform:rotate(-12deg) scale(1.08)}
  .bm-nav-links{display:flex;align-items:center;gap:.9rem;flex-wrap:wrap;min-width:0}
  .bm-navlink{color:#d9cdfa;font-size:.9rem;font-weight:700;text-decoration:none;transition:color .15s}
  .bm-navlink:hover{color:#fff;text-decoration:underline}
  .bm-navlink--email{max-width:12rem;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .bm-pill{display:inline-flex;align-items:center;gap:.35rem;padding:.45rem .95rem;border-radius:999px;background:rgba(255,255,255,.1);border:2px solid rgba(255,255,255,.18);color:#fff;font-weight:800;font-size:.9rem;text-decoration:none;transition:background .15s,transform .15s,border-color .15s}
  .bm-pill:hover{background:rgba(255,255,255,.18);border-color:var(--bm-yellow);transform:translateY(-1px)}
  @media (max-width:520px){.bm-navlink--email{display:none}}

  .bm-btn--ghost{background:rgba(255,255,255,.1);color:#fff;box-shadow:0 6px 0 rgba(0,0,0,.3)}
  .bm-btn--ghost:hover{box-shadow:0 8px 0 rgba(0,0,0,.3);background:rgba(255,255,255,.16)}
  .bm-btn--ghost:active{box-shadow:0 2px 0 rgba(0,0,0,.3)}
  .bm-btn--block{display:block;width:100%;box-sizing:border-box}
  .bm-btn--sm{padding:.6rem 1.1rem;font-size:.95rem}
  .bm-muted{color:#b9acdf;font-size:.95rem;line-height:1.5;margin:0}
  .bm-h2{margin:0;font-size:1.25rem;font-weight:900;color:#fff}
  .bm-note{display:flex;align-items:center;gap:.6rem;padding:.75rem 1rem;border-radius:1rem;background:rgba(45,226,230,.12);border:2px solid rgba(45,226,230,.35);color:#d6fbfc;font-weight:700;font-size:.95rem}
  .bm-note a{color:#fff}

  .bm-auth{max-width:26rem;width:100%;margin:1rem auto 0;display:flex;flex-direction:column;gap:1.1rem}
  .bm-auth .bm-title{text-align:center}
  .bm-auth .fieldset{display:block;padding:0;margin:0 0 .9rem;border:0}
  .bm-auth .label{display:block;margin-bottom:.4rem;font-weight:800;font-size:.9rem;color:#d9cdfa}
  .bm-auth .input{display:block;width:100%;box-sizing:border-box;height:auto;padding:.85rem 1.15rem;border-radius:999px;border:3px solid transparent;background:#fff;color:var(--bm-deep);font-size:1.05rem;font-weight:800;box-shadow:0 5px 0 rgba(0,0,0,.28);transition:border-color .15s}
  .bm-auth .input:focus{outline:none;border-color:var(--bm-pink)}
  .bm-auth .input[readonly]{background:#e9e2ff}
  .bm-auth .input-error{border-color:var(--bm-pink)}
  .bm-auth .text-error{color:#ffb3c6;font-weight:700}
  .bm-or{display:flex;align-items:center;gap:.8rem;color:#b9acdf;font-weight:800;font-size:.85rem;text-transform:uppercase;letter-spacing:.08em}
  .bm-or::before,.bm-or::after{content:"";flex:1;height:2px;border-radius:2px;background:rgba(255,255,255,.14)}
  .bm-details summary{cursor:pointer;color:#d9cdfa;font-weight:800;list-style:none;text-align:center}
  .bm-details summary::-webkit-details-marker{display:none}
  .bm-details summary:hover{color:#fff}
  .bm-details[open] summary{margin-bottom:1rem}

  .toast{z-index:60}
  .toast .alert{border-radius:1rem;border:2px solid rgba(255,255,255,.2);font-weight:700;box-shadow:0 8px 0 rgba(0,0,0,.25)}
  .toast .alert-info{background:#1f3f6b;color:#e6f6ff;border-color:var(--bm-cyan)}
  .toast .alert-error{background:#5a1a33;color:#ffe3ea;border-color:var(--bm-pink)}

  .bm-profile{display:flex;align-items:center;gap:1rem}
  .bm-avatar{flex:none;width:4rem;height:4rem;border-radius:50%;display:grid;place-items:center;font-size:1.8rem;font-weight:900;color:var(--bm-deep);background:linear-gradient(135deg,var(--bm-cyan),var(--bm-violet));box-shadow:0 5px 0 rgba(0,0,0,.3)}
  .bm-profile-name{margin:0;font-size:1.05rem;font-weight:800;color:#fff;overflow-wrap:anywhere}
  .bm-tiles{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.8rem}
  @media (min-width:560px){.bm-tiles{grid-template-columns:repeat(4,minmax(0,1fr))}}
  .bm-tile{padding:.9rem 1rem;border-radius:1.1rem;background:rgba(255,255,255,.07);border:2px solid rgba(255,255,255,.12);display:flex;flex-direction:column;gap:.2rem;transition:transform .15s,border-color .15s}
  .bm-tile:hover{transform:translateY(-2px);border-color:var(--t,var(--bm-yellow))}
  .bm-tile-num{font-size:1.9rem;font-weight:900;line-height:1.05;color:var(--t,var(--bm-yellow));font-variant-numeric:tabular-nums}
  .bm-tile-label{font-size:.78rem;font-weight:800;text-transform:uppercase;letter-spacing:.07em;color:#b9acdf}
  .bm-artists{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:.7rem}
  .bm-artist{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:.3rem .8rem;align-items:center}
  .bm-artist-name{font-weight:900;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .bm-artist-count{font-size:.85rem;font-weight:700;color:#b9acdf;font-variant-numeric:tabular-nums}
  .bm-artist-bar{grid-column:1 / -1;height:8px;border-radius:999px;background:rgba(255,255,255,.1);overflow:hidden}
  .bm-artist-bar i{display:block;height:100%;border-radius:999px;background:linear-gradient(90deg,var(--bm-yellow),var(--bm-pink));transform-origin:left;animation:bm-grow .8s cubic-bezier(.2,1,.3,1) both}
  .bm-rounds{display:flex;flex-direction:column;gap:.9rem}
  .bm-round{padding:1rem 1.1rem;border-radius:1.25rem;background:rgba(36,20,71,.85);border:2px solid rgba(255,255,255,.12);display:flex;flex-direction:column;gap:.7rem;animation:bm-in .35s ease-out}
  .bm-round-head{display:flex;align-items:center;justify-content:space-between;gap:.6rem;flex-wrap:wrap}
  .bm-round-when{font-weight:800;color:#d9cdfa;font-size:.9rem}
  .bm-round-meta{display:flex;align-items:center;gap:.5rem}
  .bm-badge{padding:.2rem .6rem;border-radius:999px;font-size:.75rem;font-weight:900;text-transform:uppercase;letter-spacing:.06em;background:rgba(255,255,255,.12);color:#fff}
  .bm-badge--deezer{background:rgba(166,108,255,.3)}
  .bm-badge--spotify{background:rgba(92,255,157,.25)}
  .bm-round-score{font-weight:900;color:var(--bm-yellow);font-variant-numeric:tabular-nums}
  .bm-plays{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:.45rem}
  .bm-play{display:flex;align-items:center;gap:.7rem;min-width:0}
  .bm-play-dot{flex:none;width:1.9rem;height:1.9rem;border-radius:50%;display:grid;place-items:center;font-size:.95rem;background:rgba(255,255,255,.1)}
  .bm-play--title .bm-play-dot{background:linear-gradient(135deg,#5cff9d,#2de2e6)}
  .bm-play--artist .bm-play-dot{background:linear-gradient(135deg,#2de2e6,#a66cff)}
  .bm-play--missed .bm-play-dot{background:rgba(255,122,153,.2)}
  .bm-play-text{min-width:0;flex:1;line-height:1.25}
  .bm-play-title{font-weight:800;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .bm-play-artist{font-size:.85rem;color:#b9acdf;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .bm-play--missed .bm-play-title{color:#ffd9e0}
  .bm-play-pts{flex:none;font-weight:900;font-size:.9rem;color:#fff;font-variant-numeric:tabular-nums}
  .bm-play--missed .bm-play-pts{color:#ff9fb6}
  .bm-empty{padding:1.4rem;border-radius:1.25rem;border:2px dashed rgba(255,255,255,.2);text-align:center;color:#d9cdfa;display:flex;flex-direction:column;align-items:center;gap:.8rem}

  .bm-kicker{margin:0;font-size:.78rem;font-weight:900;text-transform:uppercase;letter-spacing:.12em;color:#b9acdf}
  .bm-code{font-size:2.6rem;letter-spacing:.14em;font-variant-numeric:tabular-nums}
  .bm-room-head{display:flex;align-items:flex-end;justify-content:space-between;gap:1rem;flex-wrap:wrap}
  .bm-players{display:grid;grid-template-columns:repeat(auto-fill,minmax(13rem,1fr));gap:.7rem}
  .bm-player{display:flex;align-items:center;gap:.7rem;padding:.65rem .8rem;border-radius:1rem;background:rgba(255,255,255,.07);border:2px solid rgba(255,255,255,.12);min-width:0;transition:opacity .2s,border-color .2s,transform .2s;animation:bm-in .35s ease-out}
  .bm-player--me{border-color:var(--bm-yellow)}
  .bm-player--away{opacity:.45}
  .bm-player-avatar{flex:none;width:2.4rem;height:2.4rem;border-radius:50%;display:grid;place-items:center;font-weight:900;font-size:1.1rem;color:var(--bm-deep);background:var(--c);box-shadow:0 3px 0 rgba(0,0,0,.3)}
  .bm-player-text{flex:1;min-width:0;display:flex;flex-direction:column;line-height:1.2}
  .bm-player-name{font-weight:900;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .bm-player-you{font-weight:700;color:#b9acdf}
  .bm-player-meta{font-size:.8rem;font-weight:700;color:#b9acdf;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .bm-player-score{flex:none;display:flex;flex-direction:column;align-items:flex-end;font-size:1.5rem;font-weight:900;color:var(--bm-yellow);font-variant-numeric:tabular-nums;line-height:1}
  .bm-player-delta{font-size:.8rem;color:var(--bm-green);animation:bm-pop .6s cubic-bezier(.2,1.6,.4,1)}
  .bm-origin{margin-top:.25rem;font-size:.8rem;font-weight:800;opacity:.85}
  .bm-rank{display:inline-block;margin-left:.6rem;font-weight:800}
  .bm-feed{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:.45rem;font-weight:700;color:#e9e2ff}
  .bm-feed li{animation:bm-in .35s ease-out}
  .bm-feed li:first-child{color:#fff}
  .bm-feed li:not(:first-child){opacity:.75}
  .bm-home-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(16rem,1fr));gap:1rem}
  .bm-join{display:flex;flex-direction:row;align-items:flex-start;gap:.6rem;max-width:none;width:auto}
  .bm-join .fieldset{flex:1;margin:0}
  .bm-join .input{text-transform:uppercase;letter-spacing:.14em;text-align:center}

  @keyframes bm-grow{0%{transform:scaleX(0)}100%{transform:scaleX(1)}}
  @keyframes bm-pop{0%{transform:scale(.85)}40%{transform:scale(1.07) rotate(-1deg)}70%{transform:scale(.98)}100%{transform:scale(1)}}
  @keyframes bm-shake{10%,90%{transform:translateX(-2px)}20%,80%{transform:translateX(4px)}30%,50%,70%{transform:translateX(-7px)}40%,60%{transform:translateX(7px)}}
  @keyframes bm-eq{0%,100%{transform:scaleY(.25)}50%{transform:scaleY(1)}}
  @keyframes bm-float{0%{opacity:0;transform:translateY(8px) scale(.6)}20%{opacity:1;transform:translateY(0) scale(1.3)}100%{opacity:0;transform:translateY(-46px) scale(1)}}
  @keyframes bm-bump{0%{transform:scale(1)}40%{transform:scale(1.55);color:#fff}100%{transform:scale(1)}}
  @keyframes bm-pulse{0%,100%{transform:scale(1)}50%{transform:scale(1.08)}}
  @keyframes bm-in{0%{opacity:0;transform:translateY(8px)}100%{opacity:1;transform:translateY(0)}}
  @media (prefers-reduced-motion: reduce){.bm-player,.bm-player-delta,.bm-feed li,.bm-round,.bm-artist-bar i,.bm-logo,.bm-tile,.bm-slot,.bm-score-num,.bm-banner,.bm-float,.bm-eq i,.bm-timer--low,.bm-feedback,.bm-form.bm-shake{animation:none!important}}
  """

  def css, do: @css

  @doc "Insère la feuille de style du thème."
  def styles(assigns) do
    assigns = assign(assigns, :css, @css)

    ~H"""
    <style>
      <%= Phoenix.HTML.raw(@css) %>
    </style>
    """
  end
end
