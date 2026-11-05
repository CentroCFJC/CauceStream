// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer.platformview;

import android.content.Context;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
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
import io.flutter.plugins.videoplayer.VideoAsset;
import io.flutter.plugins.videoplayer.VideoPlayer;
import io.flutter.plugins.videoplayer.VideoPlayerCallbacks;
import io.flutter.plugins.videoplayer.VideoPlayerOptions;
import io.flutter.view.TextureRegistry.SurfaceProducer;
import java.util.ArrayList;
import java.util.List;

/**
 * A subclass of {@link VideoPlayer} that adds functionality related to platform view as a way of
 * displaying the video in the app.
 */
public class PlatformViewVideoPlayer extends VideoPlayer {
  private static final String TAG = "PlatformViewVideoPlayer";

  /**
   * Custom MediaCodecSelector that excludes the problematic Amlogic hardware decoder.
   * Shared logic with TextureVideoPlayer for consistency.
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

  @VisibleForTesting
  public PlatformViewVideoPlayer(
      @NonNull VideoPlayerCallbacks events,
      @NonNull MediaItem mediaItem,
      @NonNull VideoPlayerOptions options,
      @NonNull ExoPlayerProvider exoPlayerProvider) {
    super(events, mediaItem, options, /* surfaceProducer */ null, exoPlayerProvider);
  }

  /**
   * Creates a platform view video player.
   *
   * @param context application context.
   * @param events event callbacks.
   * @param asset asset to play.
   * @param options options for playback.
   * @return a video player instance.
   */
  @NonNull
  @OptIn(markerClass = UnstableApi.class)
  public static PlatformViewVideoPlayer create(
      @NonNull Context context,
      @NonNull VideoPlayerCallbacks events,
      @NonNull VideoAsset asset,
      @NonNull VideoPlayerOptions options) {
    return new PlatformViewVideoPlayer(
        events,
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

  @NonNull
  @Override
  protected ExoPlayerEventListener createExoPlayerEventListener(
      @NonNull ExoPlayer exoPlayer, @Nullable SurfaceProducer surfaceProducer) {
    // Platform view video player does not suspend and re-create the exoPlayer, hence initialized
    // is always false. It also does not require a reference to the SurfaceProducer.
    return new PlatformViewExoPlayerEventListener(exoPlayer, videoPlayerEvents, false);
  }
}
