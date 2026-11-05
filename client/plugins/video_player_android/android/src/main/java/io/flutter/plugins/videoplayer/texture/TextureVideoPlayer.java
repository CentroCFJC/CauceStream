// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer.texture;

import android.content.Context;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.annotation.RestrictTo;
import androidx.annotation.VisibleForTesting;
import androidx.media3.common.MediaItem;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.mediacodec.DefaultMediaCodecAdapterFactory;
import androidx.media3.exoplayer.mediacodec.MediaCodecAdapter;
import androidx.media3.exoplayer.mediacodec.MediaCodecInfo;
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector;
import io.flutter.plugins.videoplayer.ExoPlayerEventListener;
import io.flutter.plugins.videoplayer.ExoPlayerState;
import io.flutter.plugins.videoplayer.VideoAsset;
import io.flutter.plugins.videoplayer.VideoPlayer;
import io.flutter.plugins.videoplayer.VideoPlayerCallbacks;
import io.flutter.plugins.videoplayer.VideoPlayerOptions;
import io.flutter.view.TextureRegistry.SurfaceProducer;
import java.util.ArrayList;
import java.util.List;

/**
 * A subclass of {@link VideoPlayer} that adds functionality related to texture view as a way of
 * displaying the video in the app.
 *
 * <p>It manages the lifecycle of the texture and ensures that the video is properly displayed on
 * the texture.
 */
public final class TextureVideoPlayer extends VideoPlayer implements SurfaceProducer.Callback {
  private static final String TAG = "TextureVideoPlayer";
  @Nullable private ExoPlayerState savedStateDuring;

  /**
   * Custom MediaCodecSelector that excludes the problematic Amlogic hardware decoder
   * (OMX.amlogic.avc.decoder.awesome2) which crashes on certain video formats
   * (e.g., 1080x1080 square videos). Software decoders (OMX.google.* / c2.android.*)
   * are prioritized as fallback.
   */
  @OptIn(markerClass = UnstableApi.class)
  private static final MediaCodecSelector SAFE_CODEC_SELECTOR =
      (mimeType, requiresSecureDecoder, requiresTunnelingDecoder) -> {
        List<MediaCodecInfo> allDecoders =
            MediaCodecSelector.DEFAULT.getDecoderInfos(
                mimeType, requiresSecureDecoder, requiresTunnelingDecoder);
        List<MediaCodecInfo> filtered = new ArrayList<>();
        List<MediaCodecInfo> softwareDecoders = new ArrayList<>();

        for (MediaCodecInfo info : allDecoders) {
          String name = info.name;
          if (name.startsWith("OMX.google.") || name.startsWith("c2.android.")) {
            softwareDecoders.add(info);
          } else {
            filtered.add(info);
          }
        }

        filtered.addAll(softwareDecoders);

        Log.d(TAG, "Available decoders for " + mimeType + ": " + filtered.size());
        for (MediaCodecInfo info : filtered) {
          Log.d(TAG, "  → " + info.name);
        }

        return filtered;
      };

  /**
   * Creates a texture video player.
   *
   * @param context application context.
   * @param events event callbacks.
   * @param surfaceProducer produces a texture to render to.
   * @param asset asset to play.
   * @param options options for playback.
   * @return a video player instance.
   */
  @NonNull
  @OptIn(markerClass = UnstableApi.class)
  public static TextureVideoPlayer create(
      @NonNull Context context,
      @NonNull VideoPlayerCallbacks events,
      @NonNull SurfaceProducer surfaceProducer,
      @NonNull VideoAsset asset,
      @NonNull VideoPlayerOptions options) {
    return new TextureVideoPlayer(
        events,
        surfaceProducer,
        asset.getMediaItem(),
        options,
        () -> {
          DefaultRenderersFactory renderersFactory =
              new DefaultRenderersFactory(context) {
                @Override
                protected MediaCodecAdapter.Factory getCodecAdapterFactory() {
                  DefaultMediaCodecAdapterFactory factory =
                      new DefaultMediaCodecAdapterFactory();
                  factory.forceDisableAsynchronous();
                  return factory;
                }
              };
          // Enable decoder fallback: if one decoder fails, try the next one
          renderersFactory.setEnableDecoderFallback(true);
          // Use our custom codec selector that excludes the broken Amlogic decoder
          renderersFactory.setMediaCodecSelector(SAFE_CODEC_SELECTOR);

          ExoPlayer.Builder builder =
              new ExoPlayer.Builder(context, renderersFactory)
                  .setMediaSourceFactory(asset.getMediaSourceFactory(context));
          return builder.build();
        });
  }

  @VisibleForTesting
  public TextureVideoPlayer(
      @NonNull VideoPlayerCallbacks events,
      @NonNull SurfaceProducer surfaceProducer,
      @NonNull MediaItem mediaItem,
      @NonNull VideoPlayerOptions options,
      @NonNull ExoPlayerProvider exoPlayerProvider) {
    super(events, mediaItem, options, surfaceProducer, exoPlayerProvider);

    surfaceProducer.setCallback(this);

    this.exoPlayer.setVideoSurface(surfaceProducer.getSurface());
  }

  @NonNull
  @Override
  protected ExoPlayerEventListener createExoPlayerEventListener(
      @NonNull ExoPlayer exoPlayer, @Nullable SurfaceProducer surfaceProducer) {
    if (surfaceProducer == null) {
      throw new IllegalArgumentException(
          "surfaceProducer cannot be null to create an ExoPlayerEventListener for TextureVideoPlayer.");
    }
    boolean surfaceProducerHandlesCropAndRotation = surfaceProducer.handlesCropAndRotation();
    return new TextureExoPlayerEventListener(
        exoPlayer,
        videoPlayerEvents,
        surfaceProducerHandlesCropAndRotation,
        playerHasBeenSuspended());
  }

  @RestrictTo(RestrictTo.Scope.LIBRARY)
  public void onSurfaceAvailable() {
    if (savedStateDuring != null) {
      exoPlayer = createVideoPlayer();
      exoPlayer.setVideoSurface(surfaceProducer.getSurface());
      savedStateDuring.restore(exoPlayer);
      savedStateDuring = null;
    }
  }

  @RestrictTo(RestrictTo.Scope.LIBRARY)
  // TODO(bparrishMines): Replace with onSurfaceCleanup once available on stable. See
  // https://github.com/flutter/flutter/issues/161256.
  @SuppressWarnings({"deprecation", "removal"})
  public void onSurfaceDestroyed() {
    // Intentionally do not call pause/stop here, because the surface has already been released
    // at this point (see https://github.com/flutter/flutter/issues/156451).
    savedStateDuring = ExoPlayerState.save(exoPlayer);
    exoPlayer.release();
  }

  private boolean playerHasBeenSuspended() {
    return savedStateDuring != null;
  }

  public void dispose() {
    // Super must be called first to ensure the player is released before the surface.
    super.dispose();

    surfaceProducer.release();
    // TODO(matanlurey): Remove when embedder no longer calls-back once released.
    // https://github.com/flutter/flutter/issues/156434.
    surfaceProducer.setCallback(null);
  }
}
