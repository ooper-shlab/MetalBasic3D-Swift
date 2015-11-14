//
//  AAPLViewController.swift
//  MetalBasic3D
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/11/14.
//
//
/*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:
 View Controller for Metal Sample Code. Maintains a CADisplayLink timer that runs on the main thread and triggers rendering in AAPLView. Provides update callbacks to its delegate on the timer, prior to triggering rendering.
 */

#if os(iOS)
    import UIKit
    typealias BaseViewController = UIViewController
#else
    import AppKit
    typealias BaseViewController = NSViewController
#endif
import QuartzCore

// required view controller delegate functions.
@objc(AAPLViewControllerDelegate)
protocol AAPLViewControllerDelegate: NSObjectProtocol {
    
    // Note this method is called from the thread the main game loop is run
    func update(controller: AAPLViewController)
    
    // called whenever the main game loop is paused, such as when the app is backgrounded
    func viewController(viewController: AAPLViewController, willPause pause: Bool)
}

@objc(AAPLViewController)
class AAPLViewController: BaseViewController {
    
    weak var delegate: AAPLViewControllerDelegate?
    
    // the time interval from the last draw
    private(set) var timeSinceLastDraw: NSTimeInterval = 0.0
    
    // What vsync refresh interval to fire at. (Sets CADisplayLink frameinterval property)
    // set to 1 by default, which is the CADisplayLink default setting (60 FPS).
    // Setting to 2, will cause gameloop to trigger every other vsync (throttling to 30 FPS)
    var interval: Int = 0
    
    // app control
    
    #if os(iOS)
    private var _displayLink: CADisplayLink?
    #else
    var _displayLink: CVDisplayLink?
    var _displaySource: dispatch_source_t?
    #endif
    
    // boolean to determine if the first draw has occured
    private var _firstDrawOccurred: Bool = false
    
    private var _timeSinceLastDrawPreviousTime: CFTimeInterval = 0.0
    
    // pause/resume
    private var _gameLoopPaused: Bool = false
    
    // our renderer instance
    private var _renderer: AAPLRenderer!
    
    deinit {
        #if os(iOS)
            NSNotificationCenter.defaultCenter().removeObserver(self,
                name: UIApplicationDidEnterBackgroundNotification,
                object: nil)
            
            NSNotificationCenter.defaultCenter().removeObserver(self,
                name: UIApplicationWillEnterForegroundNotification,
                object: nil)
            
        #endif
        if _displayLink != nil {
            self.stopGameLoop()
        }
    }
    
    #if os(iOS)
    private func dispatchGameLoop() {
        // create a game loop timer using a display link
        _displayLink = UIScreen.mainScreen().displayLinkWithTarget(self,
            selector: "gameloop")
        _displayLink?.frameInterval = interval
        _displayLink?.addToRunLoop(NSRunLoop.mainRunLoop(),
            forMode: NSDefaultRunLoopMode)
    }
    
    #else
    // This is the renderer output callback function
    private let dispatchGameLoop: CVDisplayLinkOutputCallback = {(displayLink: CVDisplayLink,
        now: UnsafePointer<CVTimeStamp>,
        outputTime: UnsafePointer<CVTimeStamp>,
        flagsIn: CVOptionFlags,
        flagsOut: UnsafeMutablePointer<CVOptionFlags>,
        displayLinkContext: UnsafeMutablePointer<Void>) -> CVReturn
        in
        weak var source = unsafeBitCast(displayLinkContext, dispatch_source_t.self)
        dispatch_source_merge_data(source!, 1)
        return kCVReturnSuccess
    }
    #endif
    
    private func initCommon() {
        _renderer = AAPLRenderer()
        self.delegate = _renderer
        
        #if os(iOS)
            let notificationCenter = NSNotificationCenter.defaultCenter()
            //  Register notifications to start/stop drawing as this app moves into the background
            notificationCenter.addObserver(self,
                selector: "didEnterBackground:",
                name: UIApplicationDidEnterBackgroundNotification,
                object: nil)
            
            notificationCenter.addObserver(self,
                selector: "willEnterForeground:",
                name: UIApplicationWillEnterForegroundNotification,
                object: nil)
            
        #else
            _displaySource = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0, dispatch_get_main_queue())
            dispatch_source_set_event_handler(_displaySource!) {[weak self] in
                self?.gameloop()
            }
            dispatch_resume(_displaySource!)
            
            // Create a display link capable of being used with all active displays
            var cvReturn = CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink)
            
            assert(cvReturn == kCVReturnSuccess)
            
            cvReturn = CVDisplayLinkSetOutputCallback(_displayLink!, dispatchGameLoop, UnsafeMutablePointer(unsafeAddressOf(_displaySource!)))
            
            assert(cvReturn == kCVReturnSuccess)
            
            cvReturn = CVDisplayLinkSetCurrentCGDisplay(_displayLink!, CGMainDisplayID () )
            
            assert(cvReturn == kCVReturnSuccess)
        #endif
        
        interval = 1
    }
    
    #if os(OSX)
    @objc func _windowWillClose(notification: NSNotification) {
        // Stop the display link when the window is closing because we will
        // not be able to get a drawable, but the display link may continue
        // to fire
        
        if notification.object === self.view.window {
            CVDisplayLinkStop(_displayLink!)
            dispatch_source_cancel(_displaySource!)
        }
    }
    #endif
    
    // Called when loaded from nib
    #if os(iOS)
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: NSBundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        
        self.initCommon()
        
    }
    #else
    override init?(nibName nibNameOrNil: String?, bundle nibBundleOrNil: NSBundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.initCommon()
    }
    #endif
    
    // called when loaded from storyboard
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        self.initCommon()
        
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let renderView = self.view as! AAPLView
        renderView.delegate = _renderer
        
        // load all renderer assets before starting game loop
        _renderer.configure(renderView)
        
        #if os(OSX)
            
            let notificationCenter = NSNotificationCenter.defaultCenter()
            // Register to be notified when the window closes so we can stop the displaylink
            notificationCenter.addObserver(self,
                selector: "_windowWillClose:",
                name: NSWindowWillCloseNotification,
                object: self.view.window)
            
            
            CVDisplayLinkStart(_displayLink!)
        #endif
    }
    
    
    // The main game loop called by the timer above
    @objc func gameloop() {
        
        // tell our delegate to update itself here.
        delegate?.update(self)
        
        if !_firstDrawOccurred {
            // set up timing data for display since this is the first time through this loop
            timeSinceLastDraw             = 0.0
            _timeSinceLastDrawPreviousTime = CACurrentMediaTime()
            _firstDrawOccurred              = true
        } else {
            // figure out the time since we last we drew
            let currentTime = CACurrentMediaTime()
            
            timeSinceLastDraw = currentTime - _timeSinceLastDrawPreviousTime
            
            // keep track of the time interval between draws
            _timeSinceLastDrawPreviousTime = currentTime
        }
        
        // display (render)
        
        assert(self.view is AAPLView)
        
        // call the display method directly on the render view (setNeedsDisplay: has been disabled in the renderview by default)
        (self.view as! AAPLView).display()
    }
    
    // use invalidates the main game loop. when the app is set to terminate
    func stopGameLoop() {
        if _displayLink != nil {
            #if os(iOS)
                _displayLink!.invalidate()
            #else
                // Stop the display link BEFORE releasing anything in the view
                // otherwise the display link thread may call into the view and crash
                // when it encounters something that has been release
                CVDisplayLinkStop(_displayLink!)
                dispatch_source_cancel(_displaySource!)
                
                _displayLink = nil
                _displaySource = nil
            #endif
        }
    }
    
    // Used to pause and resume the controller.
    var paused: Bool {
        set(pause) {
            if _gameLoopPaused == pause {
                return
            }
            
            if _displayLink != nil {
                // inform the delegate we are about to pause
                delegate?.viewController(self, willPause: pause)
                
                #if os(iOS)
                    _gameLoopPaused = pause
                    _displayLink!.paused = pause
                    if pause {
                        
                        // ask the view to release textures until its resumed
                        (self.view as! AAPLView).releaseTextures()
                    }
                #else
                    if pause {
                        CVDisplayLinkStop(_displayLink!)
                    } else {
                        CVDisplayLinkStart(_displayLink!)
                    }
                #endif
                
                
            }
        }
        
        get {
            return _gameLoopPaused
        }
    }
    
    @objc func didEnterBackground(notification: NSNotification) {
        self.paused = true
    }
    
    @objc func willEnterForeground(notification: NSNotification) {
        self.paused = false
    }
    
    #if os(iOS)
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        // run the game loop
        self.dispatchGameLoop()
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        
        // end the gameloop
        self.stopGameLoop()
    }
    #endif
    
}