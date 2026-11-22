# Frieren Desk site

Jekyll source for the GitHub Pages site. It is deployed by
`.github/workflows/pages.yml` and served as a project page.

## Preview locally

Two ways, no Ruby needed on your machine for the Docker one.

### With Docker (no Ruby install)

```bash
mkdir -p site/assets/img/poses site/assets/audio site/assets/overlay
cp assets/hero-bg.jpg site/assets/img/
cp assets/overlay/*.mp4 site/assets/overlay/
cp assets/page-music.mp3 site/assets/audio/
cp assets/showcase/*.png site/assets/img/
cp quickshell/frieren/assets/frieren-icon.png site/assets/img/
cp quickshell/frieren/assets/poses/*.png site/assets/img/poses/

docker run --rm -it \
  -v "$PWD/site:/srv/jekyll" \
  -p 4000:4000 \
  jekyll/jekyll:pages \
  jekyll serve -H 0.0.0.0 --baseurl ""
```

Then open <http://localhost:4000>.

### With Ruby

```bash
cd site
bundle install
```

then copy the artwork as above and run:

```bash
bundle exec jekyll serve --baseurl ""
```

Note: `assets/img/` is populated from the repo at build time (see
`pages.yml`), so screenshots always match the current tree and no PNG
duplicates are committed. The directory is intentionally not in git.

## Add a page section

Edit `site/index.md` (Markdown with Kramdown). Layout, theme CSS and the
sparkle script live in `_layouts/default.html`, `assets/css/main.css` and
`assets/js/main.js`.
