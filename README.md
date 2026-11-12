# Blind Mix

Un blind test où **5 de tes titres likés jouent en même temps**. Reconnais-les, tape l'artiste ou le titre, et fais disparaître les pistes du mix une à une avant la fin du chrono.

Connecte ton compte **Deezer** ou **Spotify**, ou essaie le **mode démo** (classement Deezer, sans compte). Avec un profil Blind Mix, tes manches sont enregistrées et les titres tirés s'adaptent peu à peu à tes goûts.

![Accueil](docs/screenshots/accueil.webp)

## Le jeu

<table>
  <tr>
    <td width="50%"><img src="docs/screenshots/manche-en-cours.webp" alt="Manche en cours"></td>
    <td width="50%"><img src="docs/screenshots/manche-terminee.webp" alt="Manche terminée"></td>
  </tr>
  <tr>
    <td align="center"><em>Manche en cours : 5 pistes mixées, 90 secondes</em></td>
    <td align="center"><em>Fin de manche, enregistrée dans le profil</em></td>
  </tr>
</table>

- **Titre trouvé** : 5 points, la piste quitte le mix.
- **Artiste trouvé** : 2 points, la piste quitte aussi le mix (toutes les pistes de cet artiste, s'il y en a plusieurs).
- La saisie tolère les accents, la casse, la ponctuation, le « The » initial, les « (feat. …) » et les petites fautes de frappe.
- Le score se cumule de manche en manche.

## Profil et goûts musicaux

<table>
  <tr>
    <td width="68%"><img src="docs/screenshots/profil.webp" alt="Profil"></td>
    <td width="32%"><img src="docs/screenshots/profil-mobile.webp" alt="Profil sur mobile"></td>
  </tr>
  <tr>
    <td align="center"><em>Statistiques, goûts et historique</em></td>
    <td align="center"><em>Sur mobile</em></td>
  </tr>
</table>

Un profil se crée avec **une simple adresse e-mail** : on reçoit un lien de connexion, sans mot de passe (un mot de passe reste possible dans les réglages). Jouer sans profil reste possible, mais sans historique.

<img src="docs/screenshots/inscription.webp" alt="Création de profil" width="640">

La page profil montre le nombre de manches, la meilleure manche, le pourcentage de pistes reconnues, les artistes que le joueur reconnaît le mieux et l'historique complet, titre par titre.

### Comment le tirage cible tes goûts

Les titres d'une manche viennent toujours de tes likes, mais certains sortent plus souvent que d'autres selon ton historique ([`lib/blind_mix/taste.ex`](lib/blind_mix/taste.ex)) :

| Situation | Effet sur la probabilité |
| --- | --- |
| Artiste déjà reconnu | augmente à chaque fois, jusqu'à ×3 |
| Artiste raté 3 fois sans jamais être trouvé | ×0,6 |
| Titre trouvé il y a moins de 3 jours | ×0,15 (puis ×0,6 jusqu'à 14 jours) |
| Titre raté, plus de 24 h après | ×1,6 (revanche) |

Le tirage reste aléatoire : un titre favorisé est plus probable, jamais garanti. Le profil est recalculé après chaque manche.

## Lancer le projet en local

Prérequis : Elixir 1.20 / OTP 29 (par exemple via asdf), Docker pour PostgreSQL.

```bash
docker compose up -d db   # PostgreSQL de développement
mix setup                 # dépendances, base de données, assets
mix phx.server            # http://localhost:4000
```

- Les e-mails de connexion s'affichent sur [`/dev/mailbox`](http://localhost:4000/dev/mailbox).
- Le mode démo marche sans aucune configuration. Pour Deezer et Spotify, renseigne les variables d'environnement de [`.env.example`](.env.example).
- En développement, des boutons 🛠 permettent de simuler une piste trouvée ou de terminer une manche.

Tests et vérifications avant commit :

```bash
mix precommit   # compilation sans warning, format, tests
```

## Déploiement

Le CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) lance les tests puis publie l'image Docker sur GitHub Container Registry : `ghcr.io/fyndir/blind_mix` (`latest` pour `master`, `sha-…` par commit, `1.2.3` pour un tag `v1.2.3`).

Sur un serveur, avec un fichier `.env` rempli (voir [`.env.example`](.env.example)) :

```bash
docker compose pull && docker compose up -d
```

Le compose démarre l'application et sa base PostgreSQL, et applique les migrations au démarrage.

Variables principales :

| Variable | Rôle |
| --- | --- |
| `SECRET_KEY_BASE` | Clé de signature des sessions (`mix phx.gen.secret`) |
| `PHX_HOST` | Nom de domaine public |
| `DATABASE_URL` | Base PostgreSQL (fournie par le compose) |
| `MAIL_PROVIDER`, `MAIL_API_KEY`, `MAIL_FROM` | Envoi des liens de connexion (`resend`, `brevo` ou `postmark`). Sans eux, les liens sont seulement écrits dans les logs. |
| `DEEZER_*`, `SPOTIFY_*` | Applications OAuth des services musicaux |

## Stack

Phoenix 1.8 et LiveView, PostgreSQL (Ecto), authentification par lien magique (`phx.gen.auth`), Swoosh pour les e-mails, Req pour les API Deezer et Spotify.
