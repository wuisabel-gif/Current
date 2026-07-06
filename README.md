# Current

Current is an interactive generative artwork built with Flutter. Thousands of
particles move through a Perlin-noise flow field, forming luminous currents that
respond to the cursor, click, or touch position. The piece can be used as a live
web experience or as a small visual tool for composing and exporting still
frames.

The controls let you tune particle density, trail length, cursor pull, and color
palette in real time. A folded toolbar keeps the canvas unobstructed while the
art is in motion, and the PNG export renders a denser still image with stronger
stroke definition for sharing or documentation.

![Current demo](demo.gif)

**Youtube Video demo**: [https://youtu.be/3b4evyvxHKE](https://youtu.be/3b4evyvxHKE)

## Interaction demo

![Cursor interaction demo](cursor_demo.gif)

## Run locally

```sh
flutter pub get
flutter run -d chrome
```

Move the cursor, click, or drag to pull the field around the pointer. Use the
top controls to tune density, trails, cursor pull, and palette. Click `PNG` to
save the current canvas, or `Reseed` to regenerate the particles.

## Build static HTML

For a local web build:

```sh
flutter build web --release
```

For GitHub Pages on this repository:

```sh
flutter build web --release --base-href /Current/
```

The static site is generated in `build/web`.

## Deploy to GitHub Pages

This repo includes a GitHub Actions workflow at
`.github/workflows/deploy-pages.yml`. Push to `main`, then in GitHub set
`Settings > Pages > Build and deployment > Source` to `GitHub Actions`.
