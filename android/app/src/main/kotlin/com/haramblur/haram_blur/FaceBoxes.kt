package com.haramblur.haram_blur

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.util.Log
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter
import java.nio.ByteBuffer
import java.nio.ByteOrder

private const val TAG = "HaramBlur"

/**
 * Face detection on the reduced working frame.
 *
 * Runs MediaPipe's BlazeFace short-range detector (Apache-2.0, 229 KB) through
 * the LiteRT runtime the app already ships for the classifier. This replaces
 * ML Kit, whose closed-source native blobs fail F-Droid's antifeature scan, and
 * keeps the same contract: `[left, top, right, bottom]` in 0..1 for the frame,
 * expanded by a 12% margin.
 *
 * The model expects a 128x128 letterboxed input in [-1, 1] and emits 896
 * anchor-relative boxes plus one logit per anchor. Anchors follow MediaPipe's
 * SSD configuration for this model: two per cell, strides 8/16/16/16.
 */
object FaceBoxes {
    const val MARGIN = 0.12

    private const val INPUT_SIZE = 128
    private const val NUM_ANCHORS = 896
    private const val CELL_STRIDES = 4
    private const val SCORE_THRESHOLD = 0.5f
    private const val NMS_IOU = 0.3f
    private const val ASSET = "models/blaze_face_short_range.tflite"

    private val lock = Any()
    private var interpreter: Interpreter? = null
    private var inputIsFloat = true
    private var anchors: Array<FloatArray>? = null

    /** Returns `[left, top, right, bottom]` in 0..1, or an empty list. */
    fun detect(context: Context, bitmap: Bitmap): List<List<Double>> {
        if (bitmap.isRecycled || bitmap.width <= 0 || bitmap.height <= 0) {
            return emptyList()
        }
        return try {
            synchronized(lock) {
                val net = interpreter ?: load(context).also { interpreter = it }
                run(net, bitmap)
            }
        } catch (error: Throwable) {
            Log.w(TAG, "Face detection failed", error)
            emptyList()
        }
    }

    private fun load(context: Context): Interpreter {
        val bytes = context.assets.open(ASSET).use { it.readBytes() }
        val model = ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder())
        model.put(bytes)
        model.rewind()
        val net = Interpreter(model, Interpreter.Options().setNumThreads(1))
        inputIsFloat = net.getInputTensor(0).dataType() == DataType.FLOAT32
        return net
    }

    private fun run(net: Interpreter, bitmap: Bitmap): List<List<Double>> {
        val input = if (inputIsFloat) {
            ByteBuffer.allocateDirect(INPUT_SIZE * INPUT_SIZE * 3 * 4).order(ByteOrder.nativeOrder())
        } else {
            ByteBuffer.allocateDirect(INPUT_SIZE * INPUT_SIZE * 3).order(ByteOrder.nativeOrder())
        }

        // Letterbox the frame into 128x128, centred on black, the way MediaPipe's
        // ImageToTensorCalculator does for this model.
        val scale = INPUT_SIZE.toFloat() / maxOf(bitmap.width, bitmap.height)
        val drawWidth = bitmap.width * scale
        val drawHeight = bitmap.height * scale
        val left = (INPUT_SIZE - drawWidth) / 2f
        val top = (INPUT_SIZE - drawHeight) / 2f
        val square = Bitmap.createBitmap(INPUT_SIZE, INPUT_SIZE, Bitmap.Config.ARGB_8888)
        try {
            val canvas = Canvas(square)
            canvas.drawColor(Color.BLACK)
            canvas.drawBitmap(
                bitmap,
                null,
                RectF(left, top, left + drawWidth, top + drawHeight),
                Paint(Paint.FILTER_BITMAP_FLAG),
            )
            val pixels = IntArray(INPUT_SIZE * INPUT_SIZE)
            square.getPixels(pixels, 0, INPUT_SIZE, 0, 0, INPUT_SIZE, INPUT_SIZE)
            for (pixel in pixels) {
                val r = (pixel shr 16) and 0xFF
                val g = (pixel shr 8) and 0xFF
                val b = pixel and 0xFF
                if (inputIsFloat) {
                    input.putFloat(r / 127.5f - 1f)
                    input.putFloat(g / 127.5f - 1f)
                    input.putFloat(b / 127.5f - 1f)
                } else {
                    input.put(r.toByte())
                    input.put(g.toByte())
                    input.put(b.toByte())
                }
            }
        } finally {
            square.recycle()
        }
        input.rewind()

        val outputs = HashMap<Int, Any>()
        var boxIndex = -1
        var scoreIndex = -1
        for (index in 0 until net.outputTensorCount) {
            when (net.getOutputTensor(index).shape().last()) {
                16 -> {
                    outputs[index] = Array(1) { FloatArray(NUM_ANCHORS * 16) }
                    boxIndex = index
                }
                1 -> {
                    outputs[index] = Array(1) { FloatArray(NUM_ANCHORS) }
                    scoreIndex = index
                }
            }
        }
        if (boxIndex < 0 || scoreIndex < 0) {
            Log.w(TAG, "Unexpected BlazeFace output tensors")
            return emptyList()
        }
        net.runForMultipleInputsOutputs(arrayOf(input), outputs)
        @Suppress("UNCHECKED_CAST")
        val boxes = outputs[boxIndex] as Array<FloatArray>
        @Suppress("UNCHECKED_CAST")
        val scores = outputs[scoreIndex] as Array<FloatArray>

        val anchorList = anchors ?: buildAnchors().also { anchors = it }
        val candidates = ArrayList<FloatArray>(16)
        for (index in 0 until NUM_ANCHORS) {
            val score = sigmoid(scores[0][index])
            if (score < SCORE_THRESHOLD) continue
            val offset = index * 16
            val anchor = anchorList[index]
            // Model units are input pixels; anchor centres are normalised.
            val cx = boxes[0][offset] / INPUT_SIZE + anchor[0]
            val cy = boxes[0][offset + 1] / INPUT_SIZE + anchor[1]
            val halfWidth = boxes[0][offset + 2] / INPUT_SIZE / 2f
            val halfHeight = boxes[0][offset + 3] / INPUT_SIZE / 2f
            val x1 = ((cx - halfWidth) * INPUT_SIZE - left) / drawWidth
            val y1 = ((cy - halfHeight) * INPUT_SIZE - top) / drawHeight
            val x2 = ((cx + halfWidth) * INPUT_SIZE - left) / drawWidth
            val y2 = ((cy + halfHeight) * INPUT_SIZE - top) / drawHeight
            candidates.add(
                floatArrayOf(
                    x1.coerceIn(0f, 1f),
                    y1.coerceIn(0f, 1f),
                    x2.coerceIn(0f, 1f),
                    y2.coerceIn(0f, 1f),
                    score,
                ),
            )
        }

        return suppress(candidates).map { box ->
            val mx = (box[2] - box[0]) * MARGIN
            val my = (box[3] - box[1]) * MARGIN
            listOf(
                (box[0] - mx).toDouble().coerceIn(0.0, 1.0),
                (box[1] - my).toDouble().coerceIn(0.0, 1.0),
                (box[2] + mx).toDouble().coerceIn(0.0, 1.0),
                (box[3] + my).toDouble().coerceIn(0.0, 1.0),
            )
        }
    }

    private fun buildAnchors(): Array<FloatArray> {
        val anchors = ArrayList<FloatArray>(NUM_ANCHORS)
        val strides = intArrayOf(8, 16, 16, 16)
        check(strides.size == CELL_STRIDES)
        for (stride in strides) {
            val cells = INPUT_SIZE / stride
            for (y in 0 until cells) {
                for (x in 0 until cells) {
                    val cx = (x + 0.5f) / cells
                    val cy = (y + 0.5f) / cells
                    // One anchor per aspect ratio (1.0) plus the interpolated
                    // scale anchor, as in ssd_anchors_calculator.
                    anchors.add(floatArrayOf(cx, cy))
                    anchors.add(floatArrayOf(cx, cy))
                }
            }
        }
        check(anchors.size == NUM_ANCHORS) { "anchor count ${anchors.size}" }
        return anchors.toTypedArray()
    }

    private fun sigmoid(value: Float): Float = 1f / (1f + kotlin.math.exp(-value))

    private fun suppress(candidates: List<FloatArray>): List<FloatArray> {
        val sorted = candidates.sortedByDescending { it[4] }
        val kept = ArrayList<FloatArray>(sorted.size)
        for (candidate in sorted) {
            if (kept.none { iou(it, candidate) > NMS_IOU }) kept.add(candidate)
        }
        return kept
    }

    private fun iou(a: FloatArray, b: FloatArray): Float {
        val x1 = maxOf(a[0], b[0])
        val y1 = maxOf(a[1], b[1])
        val x2 = minOf(a[2], b[2])
        val y2 = minOf(a[3], b[3])
        val intersection = maxOf(0f, x2 - x1) * maxOf(0f, y2 - y1)
        val areaA = maxOf(0f, a[2] - a[0]) * maxOf(0f, a[3] - a[1])
        val areaB = maxOf(0f, b[2] - b[0]) * maxOf(0f, b[3] - b[1])
        val union = areaA + areaB - intersection
        return if (union <= 0f) 0f else intersection / union
    }
}
