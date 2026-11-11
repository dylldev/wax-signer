import MetalKit
import SwiftUI

/// Renders the melting candle with Metal. `progress` is measured work, never an invented percentage.
///
/// The renderer keeps its own smoothed value: it moves toward `progress` with a time-based ease, so a percent that
/// arrives in one jump still produces continuous motion, and a percent that arrives every frame produces none of the
/// restarts the old 0.25 s linear animation had. Smoothing never runs ahead of `progress`, so the candle finishes when
/// the job finishes.
struct WaxCandleView: UIViewRepresentable {
    var progress: Double
    var isAnimating: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isOpaque = true
        view.clearColor = MTLClearColor(red: 0.02, green: 0.012, blue: 0.01, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = true
        view.backgroundColor = UIColor(red: 0.09, green: 0.047, blue: 0.043, alpha: 1)
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.target = min(1, max(0, progress))
        context.coordinator.isAnimating = isAnimating
        view.isPaused = !isAnimating
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        view.delegate = nil
        view.isPaused = true
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        var target: Double = 0
        var isAnimating = false

        private var shown: Double = 0
        private var started = false
        private var renderer: CandleRenderer?
        private var lastTick: CFTimeInterval = 0

        func attach(to view: MTKView) {
            guard let device = view.device else { return }
            renderer = CandleRenderer(device: device, pixelFormat: view.colorPixelFormat)
            view.delegate = self
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            let now = CACurrentMediaTime()
            let dt = lastTick == 0 ? 1.0 / 60.0 : min(0.1, now - lastTick)
            lastTick = now

            if !started {
                shown = target
                started = true
            }
            if isAnimating {
                // Exponential approach: no overshoot, no restart, and it settles in about half a second.
                shown += (target - shown) * (1 - exp(-dt / 0.16))
                if abs(target - shown) < 0.0015 { shown = target }
            } else {
                shown = target
            }

            renderer?.draw(in: view, progress: Float(shown), time: now)
        }
    }
}

/// Owns the pipeline and the uniforms. Falls back to a flat fill when Metal cannot build the shader, so the sign card
/// still renders instead of showing an empty box.
private final class CandleRenderer {
    private struct Uniforms {
        var res: SIMD2<Float>
        var p: Float
        var t: Float
    }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState?

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        guard let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "vsFull"),
              let fragment = library.makeFunction(name: "fsMain")
        else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat

        self.device = device
        self.queue = queue
        self.pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
        if pipeline == nil { return nil }
    }

    func draw(in view: MTKView, progress: Float, time: CFTimeInterval) {
        guard let pipeline,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        var uniforms = Uniforms(
            res: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            p: progress,
            t: Float(time.truncatingRemainder(dividingBy: 3600))
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
