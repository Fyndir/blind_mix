defmodule BlindMixWeb.Theme do
  @moduledoc """
  Thème « pop » du jeu (CSS embarqué, aucune configuration Tailwind à toucher).

  Toutes les couleurs de texte sont explicites : le thème sombre/clair de Phoenix
  ne peut plus produire du texte blanc sur fond blanc.
  """
  use Phoenix.Component

  def styles(assigns) do
    assigns = assign(assigns, :css, css())

    ~H"""
    {Phoenix.HTML.raw("<style>" <> @css <> "</style>")}
    """
  end

  def css do
    ~S"""
    :root{--ink:#1b1340;--cream:#fffaf0;--yellow:#facc15;--pink:#ff4fa3;--cyan:#22d3ee;}
    html,body{margin:0;background:#2b0f6b;}
    .pop-page{min-height:100vh;box-sizing:border-box;padding:24px 16px 56px;color:var(--ink);
      font-family:ui-rounded,"Nunito","Segoe UI",system-ui,sans-serif;
      background:radial-gradient(circle at 12% 8%,#ff4fa3 0,transparent 38%),
        radial-gradient(circle at 88% 18%,#22d3ee 0,transparent 32%),
        linear-gradient(160deg,#7c3aed,#4c1d95 60%,#2b0f6b);}
    .pop-page *{box-sizing:border-box;}
    .pop-wrap{max-width:640px;margin:0 auto;position:relative;z-index:1;}
    .top{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:20px;}
    .pop-title{margin:0;font-weight:900;font-size:clamp(2rem,7vw,3.2rem);line-height:1;color:#fff;
      text-shadow:3px 3px 0 var(--ink);letter-spacing:-.02em;}
    .pop-title span{color:var(--yellow);}
    .pop-link{color:#fff;font-weight:800;text-decoration:underline;}
    .devbadge{display:inline-block;margin-left:8px;padding:2px 8px;font-size:.7rem;font-weight:800;
      color:var(--ink);background:#fed7aa;border:2px dashed #c2410c;border-radius:99px;vertical-align:middle;}

    .pop-card{background:var(--cream);color:var(--ink);border:3px solid var(--ink);
      border-radius:20px;box-shadow:6px 6px 0 var(--ink);}
    .pad{padding:20px;}
    .lead{margin:0 0 12px;font-size:1.15rem;font-weight:700;}
    .rules{display:flex;flex-wrap:wrap;gap:10px;margin:0 0 18px;padding:0;list-style:none;}
    .rules li{padding:6px 12px;font-weight:700;background:#fff;border:3px solid var(--ink);border-radius:99px;}
    .hint{margin:12px 0 0;font-size:.9rem;opacity:.75;}

    .pop-btn{display:inline-block;cursor:pointer;font:inherit;font-weight:800;color:var(--ink);
      background:var(--yellow);border:3px solid var(--ink);border-radius:14px;padding:12px 20px;
      box-shadow:4px 4px 0 var(--ink);text-decoration:none;text-align:center;
      transition:transform .08s,box-shadow .08s;}
    .pop-btn:hover{transform:translate(-1px,-1px);box-shadow:6px 6px 0 var(--ink);}
    .pop-btn:active{transform:translate(4px,4px);box-shadow:0 0 0 var(--ink);}
    .pop-btn[disabled]{opacity:.6;cursor:wait;}
    .pop-btn.big{font-size:1.2rem;padding:14px 26px;}
    .pop-btn.spotify{background:#1ed760;}
    .pop-btn.deezer{background:#a238ff;color:#fff;}
    .pop-btn.ghost{background:#fff;}

    .hud{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:10px 18px;}
    .hud-label{font-size:.8rem;font-weight:800;text-transform:uppercase;letter-spacing:.08em;opacity:.7;}
    .score-num{display:inline-block;font-size:2.4rem;font-weight:900;line-height:1;}
    .time-badge{font-size:1.5rem;font-weight:900;}
    .timer{height:16px;margin:14px 2px 6px;background:#fff;border:3px solid var(--ink);
      border-radius:99px;overflow:hidden;}
    .timer>i{display:block;height:100%;background:linear-gradient(90deg,#22d3ee,#4ade80);
      transition:width 1s linear;}
    .timer.urgent>i{background:linear-gradient(90deg,#fb7185,#f97316);animation:pulse .6s infinite;}

    .slot{position:relative;display:flex;align-items:center;gap:14px;padding:14px 16px;margin-top:16px;}
    .slot-num{flex:none;display:grid;place-items:center;width:46px;height:46px;font-size:1.25rem;
      font-weight:900;color:var(--ink);background:var(--accent);border:3px solid var(--ink);border-radius:50%;}
    .slot.is-playing .slot-num{animation:wiggle 1.3s ease-in-out infinite;}
    .slot-body{flex:1;min-width:0;}
    .slot-name{font-size:1.15rem;font-weight:900;overflow-wrap:anywhere;color:var(--ink);}
    .slot-sub{font-size:.95rem;font-weight:600;color:var(--ink);opacity:.8;overflow-wrap:anywhere;}
    .slot-tag{flex:none;padding:4px 10px;font-size:.8rem;font-weight:800;color:var(--ink);
      background:#fff;border:2px solid var(--ink);border-radius:99px;white-space:nowrap;}
    .slot.is-title{background:#bbf7d0;animation:popin .6s cubic-bezier(.2,1.6,.4,1);}
    .slot.is-artist{background:#bfdbfe;animation:popin .6s cubic-bezier(.2,1.6,.4,1);}
    .slot.is-missed{background:#fecdd3;animation:drop .45s ease-out;}
    .eq{display:flex;align-items:flex-end;gap:4px;height:30px;margin-bottom:4px;}
    .eq i{width:7px;height:100%;background:var(--accent);border:2px solid var(--ink);
      border-radius:3px;transform-origin:bottom;animation:eq .8s ease-in-out infinite;}
    .eq i:nth-child(2){animation-delay:-.2s}.eq i:nth-child(3){animation-delay:-.45s}
    .eq i:nth-child(4){animation-delay:-.1s}.eq i:nth-child(5){animation-delay:-.6s}

    .dev-actions{display:flex;flex-direction:column;gap:6px;}
    .dev-btn{font:inherit;font-size:.75rem;font-weight:800;color:var(--ink);background:#fed7aa;
      border:2px dashed #c2410c;border-radius:10px;padding:4px 8px;cursor:pointer;white-space:nowrap;}
    .dev-btn:hover{background:#fdba74;}
    .dev-finish{margin-top:16px;}

    .guess{display:flex;gap:10px;margin-top:20px;}
    .guess input{flex:1;min-width:0;font:inherit;font-weight:700;font-size:1.1rem;color:var(--ink);
      background:#fff;border:3px solid var(--ink);border-radius:14px;padding:12px 14px;
      box-shadow:inset 3px 3px 0 rgba(27,19,64,.12);}
    .guess input::placeholder{color:#6b628f;}
    .guess input:focus{outline:4px solid var(--yellow);outline-offset:1px;}

    .toast{margin-top:16px;padding:10px 14px;font-weight:800;color:var(--ink);
      border:3px solid var(--ink);border-radius:14px;animation:popin .4s cubic-bezier(.2,1.6,.4,1);}
    .toast.hit{background:#bbf7d0;}
    .toast.miss{background:#fecdd3;}

    .end-card{margin-top:16px;padding:18px 20px;text-align:center;}
    .end-title{margin:0;font-size:1.8rem;font-weight:900;}
    .end-sub{margin:6px 0 16px;font-weight:700;}

    .loading{display:flex;align-items:center;gap:14px;padding:18px 20px;font-weight:700;}

    .deco{position:fixed;font-size:3.2rem;color:#fff;opacity:.22;pointer-events:none;
      animation:floaty 6s ease-in-out infinite;}
    .deco.d1{top:8%;left:6%;}.deco.d2{top:68%;right:7%;animation-delay:-2s;}
    .deco.d3{bottom:8%;left:12%;animation-delay:-4s;}.deco.d4{top:26%;right:18%;animation-delay:-1s;}
    .hero{padding:28px 22px;text-align:center;}
    .hero .pop-title{color:var(--ink);text-shadow:3px 3px 0 var(--yellow);font-size:clamp(2.2rem,8vw,3.6rem);}
    .hero .pop-title span{color:var(--pink);}
    .hero-buttons{display:flex;flex-direction:column;gap:12px;margin-top:22px;}
    .demo-link{margin-top:18px;font-weight:700;color:#fff;}
    .demo-link a{color:var(--yellow);font-weight:900;}

    .float-pts{position:fixed;z-index:60;pointer-events:none;padding:0 14px;font-size:1.9rem;font-weight:900;
      color:var(--ink);background:var(--yellow);border:3px solid var(--ink);border-radius:99px;
      animation:rise 1.1s ease-out forwards;}
    .confetti{position:fixed;z-index:50;width:10px;height:14px;pointer-events:none;
      border:2px solid var(--ink);animation:confetti .95s cubic-bezier(.1,.7,.3,1) forwards;}

    @keyframes popin{0%{transform:scale(.8) rotate(-3deg)}60%{transform:scale(1.06) rotate(1deg)}100%{transform:scale(1) rotate(0)}}
    @keyframes drop{0%{transform:translateY(-10px);opacity:.4}100%{transform:none;opacity:1}}
    @keyframes wiggle{0%,100%{transform:rotate(-6deg)}50%{transform:rotate(6deg) scale(1.08)}}
    @keyframes eq{0%,100%{transform:scaleY(.25)}50%{transform:scaleY(1)}}
    @keyframes pulse{0%,100%{opacity:1}50%{opacity:.55}}
    @keyframes floaty{0%,100%{transform:translateY(0) rotate(-8deg)}50%{transform:translateY(-22px) rotate(8deg)}}
    @keyframes rise{0%{transform:translateY(0) scale(.6);opacity:0}20%{transform:translateY(-10px) scale(1.2);opacity:1}100%{transform:translateY(-70px) scale(1);opacity:0}}
    @keyframes confetti{0%{transform:translate(0,0) rotate(0);opacity:1}100%{transform:translate(var(--dx),var(--dy)) rotate(var(--rot));opacity:0}}

    @media (max-width:480px){.slot{flex-wrap:wrap}.dev-actions{flex-direction:row;width:100%}}
    @media (prefers-reduced-motion:reduce){.pop-page *,.confetti,.float-pts{animation:none!important;transition:none!important;}}
    """
  end
end
