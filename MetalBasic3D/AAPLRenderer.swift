//
//  AAPLRenderer.swift
//  MetalBasic3D
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/11/14.
//
//
/*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:
 Metal Renderer for Metal Basic 3D. Acts as the update and render delegate for the view controller and performs rendering. In MetalBasic3D, the renderer draws N cubes, whos color values change every update.
 */

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

import Metal

import simd

private let kInFlightCommandBuffers = 3

private let kNumberOfBoxes = 2
private let kBoxAmbientColors: [float4] = [
    float4(0.18, 0.24, 0.8, 1.0),
    float4(0.8, 0.24, 0.1, 1.0)
]

private let kBoxDiffuseColors: [float4] = [
    float4(0.4, 0.4, 1.0, 1.0),
    float4(0.8, 0.4, 0.4, 1.0)
]

private let kFOVY: Float = 65.0
private let kEye    = float3(0.0, 0.0, 0.0)
private let kCenter = float3(0.0, 0.0, 1.0)
private let kUp     = float3(0.0, 1.0, 0.0)

private let kWidth: Float = 0.75
private let kHeight: Float = 0.75
private let kDepth: Float = 0.75

private let kCubeVertexData: [Float] = [
    kWidth, -kHeight, kDepth,   0.0, -1.0,  0.0,
    -kWidth, -kHeight, kDepth,   0.0, -1.0, 0.0,
    -kWidth, -kHeight, -kDepth,   0.0, -1.0,  0.0,
    kWidth, -kHeight, -kDepth,  0.0, -1.0,  0.0,
    kWidth, -kHeight, kDepth,   0.0, -1.0,  0.0,
    -kWidth, -kHeight, -kDepth,   0.0, -1.0,  0.0,
    
    kWidth, kHeight, kDepth,    1.0, 0.0,  0.0,
    kWidth, -kHeight, kDepth,   1.0,  0.0,  0.0,
    kWidth, -kHeight, -kDepth,  1.0,  0.0,  0.0,
    kWidth, kHeight, -kDepth,   1.0, 0.0,  0.0,
    kWidth, kHeight, kDepth,    1.0, 0.0,  0.0,
    kWidth, -kHeight, -kDepth,  1.0,  0.0,  0.0,
    
    -kWidth, kHeight, kDepth,    0.0, 1.0,  0.0,
    kWidth, kHeight, kDepth,    0.0, 1.0,  0.0,
    kWidth, kHeight, -kDepth,   0.0, 1.0,  0.0,
    -kWidth, kHeight, -kDepth,   0.0, 1.0,  0.0,
    -kWidth, kHeight, kDepth,    0.0, 1.0,  0.0,
    kWidth, kHeight, -kDepth,   0.0, 1.0,  0.0,
    
    -kWidth, -kHeight, kDepth,  -1.0,  0.0, 0.0,
    -kWidth, kHeight, kDepth,   -1.0, 0.0,  0.0,
    -kWidth, kHeight, -kDepth,  -1.0, 0.0,  0.0,
    -kWidth, -kHeight, -kDepth,  -1.0,  0.0,  0.0,
    -kWidth, -kHeight, kDepth,  -1.0,  0.0, 0.0,
    -kWidth, kHeight, -kDepth,  -1.0, 0.0,  0.0,
    
    kWidth, kHeight,  kDepth,  0.0, 0.0,  1.0,
    -kWidth, kHeight,  kDepth,  0.0, 0.0,  1.0,
    -kWidth, -kHeight, kDepth,   0.0,  0.0, 1.0,
    -kWidth, -kHeight, kDepth,   0.0,  0.0, 1.0,
    kWidth, -kHeight, kDepth,   0.0,  0.0,  1.0,
    kWidth, kHeight,  kDepth,  0.0, 0.0,  1.0,
    
    kWidth, -kHeight, -kDepth,  0.0,  0.0, -1.0,
    -kWidth, -kHeight, -kDepth,   0.0,  0.0, -1.0,
    -kWidth, kHeight, -kDepth,  0.0, 0.0, -1.0,
    kWidth, kHeight, -kDepth,  0.0, 0.0, -1.0,
    kWidth, -kHeight, -kDepth,  0.0,  0.0, -1.0,
    -kWidth, kHeight, -kDepth,  0.0, 0.0, -1.0
]

@objc(AAPLRenderer)
class AAPLRenderer: NSObject, AAPLViewControllerDelegate, AAPLViewDelegate {
    // constant synchronization for buffering <kInFlightCommandBuffers> frames
    private var _inflight_semaphore = DispatchSemaphore(value: kInFlightCommandBuffers)
    private var _dynamicConstantBuffer: [MTLBuffer] = []
    
    // renderer global ivars
    private var _device: MTLDevice?
    private var _commandQueue: MTLCommandQueue?
    private var _defaultLibrary: MTLLibrary?
    private var _pipelineState: MTLRenderPipelineState?
    private var _vertexBuffer: MTLBuffer?
    private var _depthState: MTLDepthStencilState?
    
    // globals used in update calculation
    private var _projectionMatrix: float4x4 = float4x4()
    private var _viewMatrix: float4x4 = float4x4()
    private var _rotation: Float = 0.0
    
    private var _maxBufferBytesPerFrame: Int = 0
    private var _sizeOfConstantT: Int =  MemoryLayout<AAPL.constants_t>.stride
    
    // this value will cycle from 0 to g_max_inflight_buffers whenever a display completes ensuring renderer clients
    // can synchronize between g_max_inflight_buffers count buffers, and thus avoiding a constant buffer from being overwritten between draws
    private var _constantDataBufferIndex: Int = 0
    
    override init() {
        _maxBufferBytesPerFrame = _sizeOfConstantT*kNumberOfBoxes
        super.init()
    }
    
    //MARK: Configure
    
    // load all assets before triggering rendering
    func configure(_ view: AAPLView) {
        // find a usable Device
        _device = view.device
        guard let _device = _device else {
            fatalError("MTL device not found")
        }
        
        // setup view with drawable formats
        view.depthPixelFormat   = .depth32Float
        view.stencilPixelFormat = .invalid
        view.sampleCount        = 1
        
        // create a new command queue
        _commandQueue = _device.makeCommandQueue()
        
        _defaultLibrary = _device.newDefaultLibrary()
        guard _defaultLibrary != nil else {
            NSLog(">> ERROR: Couldnt create a default shader library")
            // assert here becuase if the shader libary isn't loading, nothing good will happen
            fatalError()
        }
        
        guard self.preparePipelineState(view) else {
            NSLog(">> ERROR: Couldnt create a valid pipeline state")
            
            // cannot render anything without a valid compiled pipeline state object.
            fatalError()
        }
        
        let depthStateDesc = MTLDepthStencilDescriptor()
        depthStateDesc.depthCompareFunction = .less
        depthStateDesc.isDepthWriteEnabled = true
        _depthState = _device.makeDepthStencilState(descriptor: depthStateDesc)
        
        // allocate a number of buffers in memory that matches the sempahore count so that
        // we always have one self contained memory buffer for each buffered frame.
        // In this case triple buffering is the optimal way to go so we cycle through 3 memory buffers
        _dynamicConstantBuffer = []
        for i in 0..<kInFlightCommandBuffers {
            _dynamicConstantBuffer.append(_device.makeBuffer(length: _maxBufferBytesPerFrame, options: []))
            _dynamicConstantBuffer[i].label = "ConstantBuffer\(i)"
            
            // write initial color values for both cubes (at each offset).
            // Note, these will get animated during update
            let constant_buffer = _dynamicConstantBuffer[i].contents().assumingMemoryBound(to: AAPL.constants_t.self)
            for j in 0..<kNumberOfBoxes {
                if j%2 == 0 {
                    constant_buffer[j].multiplier = 1
                    constant_buffer[j].ambient_color = kBoxAmbientColors[0]
                    constant_buffer[j].diffuse_color = kBoxDiffuseColors[0]
                } else {
                    constant_buffer[j].multiplier = -1
                    constant_buffer[j].ambient_color = kBoxAmbientColors[1]
                    constant_buffer[j].diffuse_color = kBoxDiffuseColors[1]
                }
            }
        }
    }
    
    private func preparePipelineState(_ view: AAPLView) -> Bool {
        // get the fragment function from the library
        let fragmentProgram = _defaultLibrary?.makeFunction(name: "lighting_fragment")
        if fragmentProgram == nil {
            NSLog(">> ERROR: Couldn't load fragment function from default library")
        }
        
        // get the vertex function from the library
        let vertexProgram = _defaultLibrary?.makeFunction(name: "lighting_vertex")
        if vertexProgram == nil {
            NSLog(">> ERROR: Couldn't load vertex function from default library")
        }
        
        // setup the vertex buffers
        _vertexBuffer = _device?.makeBuffer(bytes: kCubeVertexData, length: kCubeVertexData.count * MemoryLayout<Float>.size, options: MTLResourceOptions())
        _vertexBuffer?.label = "Vertices"
        
        // create a pipeline state descriptor which can be used to create a compiled pipeline state object
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        
        pipelineStateDescriptor.label                           = "MyPipeline"
        pipelineStateDescriptor.sampleCount                     = view.sampleCount
        pipelineStateDescriptor.vertexFunction                  = vertexProgram
        pipelineStateDescriptor.fragmentFunction                = fragmentProgram
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineStateDescriptor.depthAttachmentPixelFormat      = view.depthPixelFormat
        
        // create a compiled pipeline state object. Shader functions (from the render pipeline descriptor)
        // are compiled when this is created unlessed they are obtained from the device's cache
        do {
            _pipelineState = try _device?.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        } catch let error as NSError {
            NSLog(">> ERROR: Failed Aquiring pipeline state: \(error)")
            return false
        }
        
        return true
    }
    
    //MARK: Render
    
    func render(_ view: AAPLView) {
        // Allow the renderer to preflight 3 frames on the CPU (using a semapore as a guard) and commit them to the GPU.
        // This semaphore will get signaled once the GPU completes a frame's work via addCompletedHandler callback below,
        // signifying the CPU can go ahead and prepare another frame.
        _ = _inflight_semaphore.wait(timeout: DispatchTime.distantFuture)
        
        // Prior to sending any data to the GPU, constant buffers should be updated accordingly on the CPU.
        self.updateConstantBuffer()
        
        // create a new command buffer for each renderpass to the current drawable
        let commandBuffer = _commandQueue?.makeCommandBuffer()
        
        // create a render command encoder so we can render into something
        if let renderPassDescriptor = view.renderPassDescriptor {
            let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
            renderEncoder?.pushDebugGroup("Boxes")
            renderEncoder?.setDepthStencilState(_depthState)
            renderEncoder?.setRenderPipelineState(_pipelineState!)
            renderEncoder?.setVertexBuffer(_vertexBuffer, offset: 0, at: 0)
            
            for i in 0..<kNumberOfBoxes {
                //  set constant buffer for each box
                renderEncoder?.setVertexBuffer(_dynamicConstantBuffer[_constantDataBufferIndex], offset: i*_sizeOfConstantT, at: 1)
                
                // tell the render context we want to draw our primitives
                renderEncoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36)
            }
            
            renderEncoder?.endEncoding()
            renderEncoder?.popDebugGroup()
            
            // schedule a present once rendering to the framebuffer is complete
            commandBuffer?.present(view.currentDrawable!)
        }
        
        // call the view's completion handler which is required by the view since it will signal its semaphore and set up the next buffer
        let block_sema = _inflight_semaphore
        commandBuffer?.addCompletedHandler{buffer in
            
            // GPU has completed rendering the frame and is done using the contents of any buffers previously encoded on the CPU for that frame.
            // Signal the semaphore and allow the CPU to proceed and construct the next frame.
            block_sema.signal()
        }
        
        // finalize rendering here. this will push the command buffer to the GPU
        commandBuffer?.commit()
        
        // This index represents the current portion of the ring buffer being used for a given frame's constant buffer updates.
        // Once the CPU has completed updating a shared CPU/GPU memory buffer region for a frame, this index should be updated so the
        // next portion of the ring buffer can be written by the CPU. Note, this should only be done *after* all writes to any
        // buffers requiring synchronization for a given frame is done in order to avoid writing a region of the ring buffer that the GPU may be reading.
        _constantDataBufferIndex = (_constantDataBufferIndex + 1) % kInFlightCommandBuffers
    }
    
    func reshape(_ view: AAPLView) {
        // when reshape is called, update the view and projection matricies since this means the view orientation or size changed
        let aspect = Float(abs(view.bounds.size.width / view.bounds.size.height))
        _projectionMatrix = AAPL.perspective_fov(kFOVY, aspect, 0.1, 100.0)
        _viewMatrix = AAPL.lookAt(kEye, kCenter, kUp)
    }
    
    //MARK: Update
    
    // called every frame
    private func updateConstantBuffer() {
        var baseModelViewMatrix = AAPL.translate(0.0, 0.0, 5.0) * AAPL.rotate(_rotation, 1.0, 1.0, 1.0)
        baseModelViewMatrix = _viewMatrix * baseModelViewMatrix
        
        let constant_buffer = _dynamicConstantBuffer[_constantDataBufferIndex].contents().assumingMemoryBound(to: AAPL.constants_t.self)
        for i in 0..<kNumberOfBoxes {
            // calculate the Model view projection matrix of each box
            // for each box, if its odd, create a negative multiplier to offset boxes in space
            let multiplier = ((i % 2 == 0) ? 1 : -1)
            var modelViewMatrix = AAPL.translate(0.0, 0.0, Float(multiplier)*1.5) * AAPL.rotate(_rotation, 1.0, 1.0, 1.0)
            modelViewMatrix = baseModelViewMatrix * modelViewMatrix
            
            constant_buffer[i].normal_matrix = modelViewMatrix.transpose.inverse
            constant_buffer[i].modelview_projection_matrix = _projectionMatrix * modelViewMatrix
            
            // change the color each frame
            // reverse direction if we've reached a boundary
            if constant_buffer[i].ambient_color.y >= 0.8 {
                constant_buffer[i].multiplier = -1
                constant_buffer[i].ambient_color.y = 0.79
            } else if constant_buffer[i].ambient_color.y <= 0.2 {
                constant_buffer[i].multiplier = 1
                constant_buffer[i].ambient_color.y = 0.21
            } else {
                constant_buffer[i].ambient_color.y += Float(constant_buffer[i].multiplier) * 0.01*Float(i)
            }
        }
    }
    
    // just use this to update app globals
    func update(_ controller: AAPLViewController) {
        _rotation += Float(controller.timeSinceLastDraw * 50.0)
    }
    
    func viewController(_ viewController: AAPLViewController, willPause pause: Bool) {
        // timer is suspended/resumed
        // Can do any non-rendering related background work here when suspended
    }
    
    
}
