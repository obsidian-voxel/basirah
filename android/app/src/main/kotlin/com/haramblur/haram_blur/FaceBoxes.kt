package com.haramblur.haram_blur

import android.graphics.Bitmap
import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import java.util.concurrent.TimeUnit

private const val TAG = "HaramBlur"

/**
 * ML Kit face detection on the reduced working frame.
 *
 * The model ships inside the app (bundled face-detection artifact), so this
 * works offline. Boxes are normalised to the frame and expanded by a 12%
 * margin: the margin covers the gap between this detector and the Haar cascade
 * the offline oracle uses, so the runtime and the eval agree on what counts as
 * face skin.
 */
object FaceBoxes {
    const val MARGIN = 0.12

    private val detector by lazy {
        FaceDetection.getClient(
            FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                .build(),
        )
    }

    /** Returns `[left, top, right, bottom]` in 0..1, or an empty list. */
    fun detect(bitmap: Bitmap): List<List<Double>> {
        if (bitmap.isRecycled || bitmap.width <= 0 || bitmap.height <= 0) {
            return emptyList()
        }
        return try {
            val faces = Tasks.await(
                detector.process(InputImage.fromBitmap(bitmap, 0)),
                3,
                TimeUnit.SECONDS,
            )
            val width = bitmap.width.toDouble()
            val height = bitmap.height.toDouble()
            faces.mapNotNull { face ->
                val box = face.boundingBox
                if (box.width() <= 0 || box.height() <= 0) return@mapNotNull null
                val mx = box.width() * MARGIN
                val my = box.height() * MARGIN
                listOf(
                    ((box.left - mx) / width).coerceIn(0.0, 1.0),
                    ((box.top - my) / height).coerceIn(0.0, 1.0),
                    ((box.right + mx) / width).coerceIn(0.0, 1.0),
                    ((box.bottom + my) / height).coerceIn(0.0, 1.0),
                )
            }
        } catch (error: Throwable) {
            Log.w(TAG, "Face detection failed", error)
            emptyList()
        }
    }
}
