//
//  AAPLView.swift
//  MetalBasic3D
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/11/14.
//
//
/*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:
 View for Metal Sample Code. Manages screen drawable framebuffers and expects a delegate to repond to render commands to perform drawing.
 */

import QuartzCore
import Metal

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif


#if os(iOS)
    typealias BaseView = UIView
#else
    typealias BaseView = NSView
#endif

// rendering delegate (App must implement a rendering delegate that responds to these messages
@objc(AAPLViewDelegate)
protocol AAPLViewDelegate: NSObjectProtocol {
    
    // called if the view changes orientation or size, renderer can precompute its view and projection matricies here for example
    func reshape(_ view: AAPLView)
    
    // delegate should perform all rendering here
    func render(_ view: AAPLView)
    
}

@objc(AAPLView)
class AAPLView: BaseView {
    weak var delegate: AAPLViewDelegate?
    
    // view has a handle to the metal device when created
    private(set) var device: MTLDevice!
    
    private var _currentDrawable: CAMetalDrawable?
    
    private var _renderPassDescriptor: MTLRenderPassDescriptor?
    
    // set these pixel formats to have the main drawable framebuffer get created with depth and/or stencil attachments
    var depthPixelFormat: MTLPixelFormat = .invalid
    var stencilPixelFormat: MTLPixelFormat = .invalid
    var sampleCount: Int = 0
    
    private weak var _metalLayer: CAMetalLayer!
    
    private var _layerSizeDidUpdate: Bool = false
    
    private var _depthTex: MTLTexture?
    private var _stencilTex: MTLTexture?
    private var _msaaTex: MTLTexture?
    
    #if os(iOS)
    override class var layerClass: AnyClass {
        return CAMetalLayer.self
    }
    #endif
    
    private func initCommon() {
        #if os(iOS)
            self.isOpaque = true
            self.backgroundColor = nil
            _metalLayer = (self.layer as! CAMetalLayer)
        #else
            self.wantsLayer = true
            let metalLayer = CAMetalLayer()
            _metalLayer = metalLayer
            self.layer = _metalLayer
        #endif
        
        device = MTLCreateSystemDefaultDevice()!
        
        _metalLayer.device          = device
        _metalLayer.pixelFormat     = .bgra8Unorm
        
        // this is the default but if we wanted to perform compute on the final rendering layer we could set this to no
        _metalLayer.framebufferOnly = true
    }
    
    #if os(iOS)
    override func didMoveToWindow() {
        self.contentScaleFactor = self.window!.screen.nativeScale
    }
    #endif
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.initCommon()
        
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        self.initCommon()
    }
    
    // release any color/depth/stencil resources. view controller will call when paused.
    func releaseTextures() {
        _depthTex   = nil
        _stencilTex = nil
        _msaaTex    = nil
    }
    
    private func setupRenderPassDescriptorForTexture(_ texture: MTLTexture) {
        // create lazily
        if _renderPassDescriptor == nil {
            _renderPassDescriptor = MTLRenderPassDescriptor()
        }
        
        // create a color attachment every frame since we have to recreate the texture every frame
        let colorAttachment = _renderPassDescriptor!.colorAttachments[0]
        colorAttachment?.texture = texture
        
        // make sure to clear every frame for best performance
        colorAttachment?.loadAction = .clear
        colorAttachment?.clearColor = MTLClearColorMake(0.65, 0.65, 0.65, 1.0)
        
        // if sample count is greater than 1, render into using MSAA, then resolve into our color texture
        if sampleCount > 1 {
            let  doUpdate =     ( _msaaTex?.width       != texture.width  )
                ||  ( _msaaTex?.height      != texture.height )
                ||  ( _msaaTex?.sampleCount != sampleCount   )
            
            if _msaaTex == nil || (_msaaTex != nil && doUpdate) {
                let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                    width: texture.width,
                    height: texture.height,
                    mipmapped: false)
                desc.textureType = .type2DMultisample
                
                // sample count was specified to the view by the renderer.
                // this must match the sample count given to any pipeline state using this render pass descriptor
                desc.sampleCount = sampleCount
                
                _msaaTex = device?.makeTexture(descriptor: desc)
            }
            
            // When multisampling, perform rendering to _msaaTex, then resolve
            // to 'texture' at the end of the scene
            colorAttachment?.texture = _msaaTex
            colorAttachment?.resolveTexture = texture
            
            // set store action to resolve in this case
            colorAttachment?.storeAction = MTLStoreAction.multisampleResolve
        } else {
            // store only attachments that will be presented to the screen, as in this case
            colorAttachment?.storeAction = MTLStoreAction.store
        }
        
        // Now create the depth and stencil attachments
        
        if depthPixelFormat != .invalid {
            let doUpdate =     ( _depthTex?.width       != texture.width  )
                ||  ( _depthTex?.height      != texture.height )
                ||  ( _depthTex?.sampleCount != sampleCount   )
            
            if _depthTex == nil || doUpdate {
                //  If we need a depth texture and don't have one, or if the depth texture we have is the wrong size
                //  Then allocate one of the proper size
                let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: depthPixelFormat,
                    width: texture.width,
                    height: texture.height,
                    mipmapped: false)
                
                desc.textureType = (sampleCount > 1) ? .type2DMultisample : .type2D
                desc.sampleCount = sampleCount
                desc.usage = MTLTextureUsage()
                desc.storageMode = .private
                
                _depthTex = device?.makeTexture(descriptor: desc)
                
                if let depthAttachment = _renderPassDescriptor?.depthAttachment {
                    depthAttachment.texture = _depthTex
                    depthAttachment.loadAction = .clear
                    depthAttachment.storeAction = .dontCare
                    depthAttachment.clearDepth = 1.0
                }
            }
        }
        
        if stencilPixelFormat != .invalid {
            let doUpdate  =    ( _stencilTex?.width       != texture.width  )
                ||  ( _stencilTex?.height      != texture.height )
                ||  ( _stencilTex?.sampleCount != sampleCount   )
            
            if _stencilTex == nil || doUpdate {
                //  If we need a stencil texture and don't have one, or if the depth texture we have is the wrong size
                //  Then allocate one of the proper size
                let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: stencilPixelFormat,
                    width: texture.width,
                    height: texture.height,
                    mipmapped: false)
                
                desc.textureType = (sampleCount > 1) ? .type2DMultisample : .type2D
                desc.sampleCount = sampleCount
                
                _stencilTex = device?.makeTexture(descriptor: desc)
                
                if let stencilAttachment = _renderPassDescriptor?.stencilAttachment {
                    stencilAttachment.texture = _stencilTex
                    stencilAttachment.loadAction = .clear
                    stencilAttachment.storeAction = .dontCare
                    stencilAttachment.clearStencil = 0
                }
            }
        }
    }
    
    // The current framebuffer can be read by delegate during -[MetalViewDelegate render:]
    // This call may block until the framebuffer is available.
    var renderPassDescriptor: MTLRenderPassDescriptor? {
        if let drawable = self.currentDrawable {
            self.setupRenderPassDescriptorForTexture(drawable.texture)
        } else {
            NSLog(">> ERROR: Failed to get a drawable!")
            _renderPassDescriptor = nil
        }
        
        return _renderPassDescriptor
    }
    
    
    //// the current drawable created within the view's CAMetalLayer
    var currentDrawable: CAMetalDrawable? {
        if _currentDrawable == nil {
            _currentDrawable = _metalLayer.nextDrawable()
        }
        
        return _currentDrawable!
    }
    
    //// view controller will be call off the main thread
    #if os(iOS)
    func display() {
        self.displayPrivate()
    }
    #else
    override func display() {
        self.displayPrivate()
    }
    #endif
    private func displayPrivate() {
        // Create autorelease pool per frame to avoid possible deadlock situations
        // because there are 3 CAMetalDrawables sitting in an autorelease pool.
        
        autoreleasepool{
            // handle display changes here
            if _layerSizeDidUpdate {
                // set the metal layer to the drawable size in case orientation or size changes
                var drawableSize = self.bounds.size
                
                // scale drawableSize so that drawable is 1:1 width pixels not 1:1 to points
                #if os(iOS)
                    let screen = self.window?.screen ?? UIScreen.main
                    drawableSize.width *= screen.nativeScale
                    drawableSize.height *= screen.nativeScale
                #else
                    let screen = self.window?.screen ?? NSScreen.main
                    drawableSize.width *= screen?.backingScaleFactor ?? 1.0
                    drawableSize.height *= screen?.backingScaleFactor ?? 1.0
                #endif
                
                _metalLayer.drawableSize = drawableSize
                
                // renderer delegate method so renderer can resize anything if needed
                delegate?.reshape(self)
                
                _layerSizeDidUpdate = false
            }
            
            // rendering delegate method to ask renderer to draw this frame's content
            self.delegate?.render(self)
            
            // do not retain current drawable beyond the frame.
            // There should be no strong references to this object outside of this view class
            _currentDrawable    = nil
        }
    }
    
    #if os(iOS)
    override var contentScaleFactor: CGFloat {
        get {
            return super.contentScaleFactor
        }
        set {
            super.contentScaleFactor = newValue
            _layerSizeDidUpdate = true
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        _layerSizeDidUpdate = true
    }
    #else
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        _layerSizeDidUpdate = true
    }
    
    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        _layerSizeDidUpdate = true
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        _layerSizeDidUpdate = true
    }
    #endif
    
}
