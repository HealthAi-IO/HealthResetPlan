import Flutter
import MetalKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = registrar(forPlugin: "LifeTrajectoryView") {
      registrar.register(
        LifeTrajectoryViewFactory(),
        withId: "health_reset_plan/life_trajectory"
      )
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

private final class LifeTrajectoryViewFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    LifeTrajectoryPlatformView(frame: frame, arguments: args)
  }
}

private final class LifeTrajectoryPlatformView: NSObject, FlutterPlatformView {
  private let metalView: MTKView
  private var renderer: LifeTrajectoryRenderer?

  init(frame: CGRect, arguments: Any?) {
    metalView = MTKView(frame: frame, device: MTLCreateSystemDefaultDevice())
    super.init()
    metalView.isOpaque = false
    metalView.backgroundColor = .clear
    metalView.clearColor = MTLClearColorMake(0, 0, 0, 0)
    metalView.colorPixelFormat = .bgra8Unorm
    metalView.isPaused = true
    metalView.enableSetNeedsDisplay = true

    let params = arguments as? [String: Any]
    let values = (params?["values"] as? [NSNumber])?.map { $0.floatValue } ?? []
    let lineWidth = (params?["lineWidth"] as? NSNumber)?.floatValue ?? 5
    renderer = LifeTrajectoryRenderer(
      view: metalView,
      values: values,
      lineWidth: lineWidth
    )
    metalView.delegate = renderer
    metalView.setNeedsDisplay()
  }

  func view() -> UIView { metalView }
}

private final class LifeTrajectoryRenderer: NSObject, MTKViewDelegate {
  private let commandQueue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState
  private var values: [Float]
  private var metadata: SIMD2<Float>

  init?(view: MTKView, values: [Float], lineWidth: Float) {
    guard
      let device = view.device,
      let commandQueue = device.makeCommandQueue(),
      let library = try? device.makeLibrary(source: Self.shaderSource),
      let vertex = library.makeFunction(name: "trajectoryVertex"),
      let fragment = library.makeFunction(name: "trajectoryFragment")
    else { return nil }

    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = vertex
    descriptor.fragmentFunction = fragment
    descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
    descriptor.colorAttachments[0].isBlendingEnabled = true
    descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
    descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
      return nil
    }

    self.commandQueue = commandQueue
    self.pipeline = pipeline
    self.values = Array(values.prefix(8))
    if self.values.count < 2 {
      self.values = [0.38, 0.46, 0.43, 0.56, 0.52, 0.68]
    }
    self.metadata = SIMD2(Float(self.values.count), max(lineWidth, 1))
    super.init()
  }

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

  func draw(in view: MTKView) {
    guard
      let descriptor = view.currentRenderPassDescriptor,
      let drawable = view.currentDrawable,
      let commandBuffer = commandQueue.makeCommandBuffer(),
      let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
    else { return }

    encoder.setRenderPipelineState(pipeline)
    values.withUnsafeBytes { buffer in
      if let address = buffer.baseAddress {
        encoder.setFragmentBytes(address, length: buffer.count, index: 0)
      }
    }
    encoder.setFragmentBytes(
      &metadata,
      length: MemoryLayout<SIMD2<Float>>.stride,
      index: 1
    )
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }

  private static let shaderSource = """
  #include <metal_stdlib>
  using namespace metal;

  struct RasterData {
    float4 position [[position]];
    float2 uv;
  };

  vertex RasterData trajectoryVertex(uint vertexId [[vertex_id]]) {
    const float2 positions[3] = {
      float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0)
    };
    RasterData out;
    out.position = float4(positions[vertexId], 0.0, 1.0);
    out.uv = positions[vertexId] * 0.5 + 0.5;
    return out;
  }

  fragment float4 trajectoryFragment(
    RasterData in [[stage_in]],
    constant float *values [[buffer(0)]],
    constant float2 &metadata [[buffer(1)]]
  ) {
    const int count = max(2, int(metadata.x));
    const float scaled = clamp(in.uv.x, 0.0, 0.9999) * float(count - 1);
    const int index = min(int(floor(scaled)), count - 2);
    const float local = smoothstep(0.0, 1.0, fract(scaled));
    const float value = mix(values[index], values[index + 1], local);
    const float targetY = 0.90 - value * 0.72;
    const float width = max(0.012, metadata.y / 420.0);
    const float alpha = 1.0 - smoothstep(width, width + 0.012, abs(in.uv.y - targetY));
    const float3 blue = float3(0.09, 0.41, 0.88);
    const float3 cyan = float3(0.26, 0.85, 0.80);
    const float3 green = float3(0.48, 0.90, 0.43);
    const float3 color = in.uv.x < 0.65
      ? mix(blue, cyan, in.uv.x / 0.65)
      : mix(cyan, green, (in.uv.x - 0.65) / 0.35);
    return float4(color, alpha);
  }
  """
}
