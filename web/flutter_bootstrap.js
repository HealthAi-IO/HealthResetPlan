{{flutter_js}}
{{flutter_build_config}}

(async () => {
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker
      .getRegistrations()
      .then((registrations) =>
        Promise.all(registrations.map((registration) => registration.unregister())),
      );
  }

  const engineConfig = {
    canvasKitBaseUrl: 'canvaskit/',
    fontFallbackBaseUrl: 'font-fallback/',
  };

  if ('ImageDecoder' in window && 'Segmenter' in Intl) {
    fetch('canvaskit/chromium/canvaskit.wasm', { cache: 'force-cache' }).catch(
      () => null,
    );
  }

  _flutter.loader.load({
    config: engineConfig,
    onEntrypointLoaded: async (engineInitializer) => {
      const appRunner = await engineInitializer.initializeEngine(engineConfig);
      await appRunner.runApp();

      const loading = document.getElementById('app-loading');
      if (loading) {
        loading.classList.add('is-hidden');
        loading.addEventListener('transitionend', () => loading.remove(), {
          once: true,
        });
      }
    },
  });
})();
