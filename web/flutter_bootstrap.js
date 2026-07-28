{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
    canvasKitVariant: 'full',
  },
  onEntrypointLoaded: async (engineInitializer) => {
    const appRunner = await engineInitializer.initializeEngine();
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
