package io.flutter.plugins.videoplayer.texture;

import android.view.Surface;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import io.flutter.view.TextureRegistry;
import io.flutter.view.TextureRegistry.SurfaceProducer;

public final class SurfaceTextureSurfaceProducer implements SurfaceProducer {

  private final TextureRegistry.SurfaceTextureEntry entry;
  private final Surface surface;
  @Nullable private Callback callback;

  public SurfaceTextureSurfaceProducer(TextureRegistry.SurfaceTextureEntry entry) {
    this.entry = entry;
    this.surface = new Surface(entry.surfaceTexture());
  }

  @Override
  public void setSize(int width, int height) {}

  @Override
  public int getWidth() {
    return 0;
  }

  @Override
  public int getHeight() {
    return 0;
  }

  @Override
  @NonNull
  public Surface getSurface() {
    return surface;
  }

  @Override
  @NonNull
  public Surface getForcedNewSurface() {
    return surface;
  }

  @Override
  public void setCallback(@Nullable Callback callback) {
    this.callback = callback;
  }

  @Override
  public void scheduleFrame() {}

  @Override
  public boolean handlesCropAndRotation() {
    // Este productor renderiza sobre un SurfaceTextureEntry legado. En esa
    // vía los fotogramas llegan a la GPU ya correctamente rotados (el
    // decodificador aplica la rotación del contenedor al renderizar al
    // Surface y el motor aplica la matriz de la textura al muestrear),
    // igual que el SurfaceProducer SurfaceTexture del motor devuelve true.
    // Devolver false provocaba que TextureExoPlayerEventListener informara
    // rotationCorrection = format.rotationDegrees y video_player volviera
    // a rotar (RotatedBox) vídeos verticales ya enderezados: doble
    // rotación, persona acostada.
    return true;
  }

  @Override
  public long id() {
    return entry.id();
  }

  @Override
  public void release() {
    surface.release();
    entry.release();
  }
}
