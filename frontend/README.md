# asi_dashboard

A new Flutter project.

## Running the app (web)

- **Development (with hot reload):**  
  `flutter run -d chrome`  
  Keep this terminal open. Use **`r`** (hot reload) or **`R`** (hot restart) in the terminal instead of refreshing the browser — much faster than a full reload.

- **Faster load when you do refresh:**  
  `flutter run -d chrome --release`  
  Builds optimized code so the app loads quicker in the browser (hot reload is not available in release).

- **Why refresh is slow:**  
  In debug mode, Flutter serves a large, unoptimized JavaScript bundle. Refreshing the page re-downloads and runs all of it. Use hot reload (`r`) during development to avoid that.

- **Run on one port only (no Chrome auto-open):**  
  `flutter run -d web-server --web-port=8080`  
  Serves the app at **http://localhost:8080**. Open that URL in any browser. Same hot reload (`r` / `R`) in the terminal. To use a different port, change `8080` (e.g. `--web-port=3000`).

- **Chrome on a fixed port:**  
  `flutter run -d chrome --web-port=8080`  
  Dev server listens on port 8080 and Chrome opens to it.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
